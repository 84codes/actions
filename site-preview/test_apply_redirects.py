import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


SCRIPT = Path(__file__).with_name("apply-redirects.sh")


class ApplyRedirectsTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        self.redirects = root / "redirects.json"
        self.events = root / "events.jsonl"
        self.env = {
            **os.environ,
            "PATH": f"{root}{os.pathsep}{os.environ['PATH']}",
            "BUCKET": "pr-123.example.dev",
            "REDIRECTS_FILE": str(self.redirects),
            "AWS_TEST_EVENTS": str(self.events),
        }
        aws = root / "aws"
        aws.write_text(f"#!{sys.executable}\n" + textwrap.dedent("""\
            import fcntl
            import json
            import os
            import sys
            import time

            def record(event):
                with open(os.environ["AWS_TEST_EVENTS"], "a") as log:
                    fcntl.flock(log, fcntl.LOCK_EX)
                    log.write(json.dumps([event, sys.argv[1:]]) + "\\n")

            record("start")
            time.sleep(0.1)
            record("end")
            if sys.argv[sys.argv.index("--key") + 1] == "broken.html":
                print("Simulated S3 upload failure", file=sys.stderr)
                sys.exit(1)
            """))
        aws.chmod(0o755)

    def run_script(self):
        return subprocess.run(
            [str(SCRIPT)], env=self.env, capture_output=True, text=True, timeout=15
        )

    def test_uploads_preserve_arguments_and_limit_concurrency(self):
        redirects = {f"old/{i}.html": f"/new/{i}.html" for i in range(20)}
        redirects["quotes' spaces\tand\nnewlines.html"] = (
            "/target?name=it's quoted&value=\"hello\"&literal=$(false);*"
        )
        self.redirects.write_text(json.dumps(redirects))

        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        active = peak = 0
        uploads = []
        for line in self.events.read_text().splitlines():
            event, args = json.loads(line)
            if event == "start":
                active += 1
                peak = max(peak, active)
                uploads.append(args)
            else:
                active -= 1
        self.assertEqual(active, 0)
        self.assertGreater(peak, 1)
        self.assertLessEqual(peak, 8)
        self.assertCountEqual(uploads, [
            [
                "s3api", "put-object", "--bucket", self.env["BUCKET"],
                "--key", source, "--website-redirect-location", target,
                "--content-type", "text/html;charset=utf-8",
            ]
            for source, target in redirects.items()
        ])

    def test_failed_upload_fails_the_step(self):
        self.redirects.write_text(json.dumps({
            "ok.html": "/ok/",
            "broken.html": "/broken/",
            "also-ok.html": "/also-ok/",
        }))

        result = self.run_script()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Simulated S3 upload failure", result.stderr)

    def test_missing_or_empty_file_does_not_upload(self):
        for contents in (None, "{}"):
            with self.subTest(contents=contents):
                if contents is not None:
                    self.redirects.write_text(contents)
                result = self.run_script()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(self.events.exists())

    def test_invalid_json_fails_before_uploading(self):
        self.redirects.write_text("not json")

        result = self.run_script()

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.events.exists())


if __name__ == "__main__":
    unittest.main()
