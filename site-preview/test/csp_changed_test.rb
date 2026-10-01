# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"

class CspChangedTest < Minitest::Test
  SCRIPT = Pathname(__dir__).join("../csp-changed.sh").expand_path
  POLICY = %({"directives": {"default-src": ["'none'"]}}\n)

  # Run the script next to the PR's policy file, with a fake gh that serves
  # base_policy as the base branch copy (nil when the base branch lacks it).
  # Returns the script output and the gh calls.
  def csp_changed(policy, base_policy)
    Dir.mktmpdir do |directory|
      directory = Pathname(directory)
      directory.join("csp-policy.json").write(policy) if policy
      directory.join("base-policy.json").write(base_policy) if base_policy
      log = directory.join("gh.log")
      log.write("")
      fake_gh(directory.join("bin"), log, directory.join("base-policy.json"))
      env = { "PATH" => "#{directory.join('bin')}:#{ENV.fetch('PATH')}" }
      output, status = Open3.capture2(env, SCRIPT.to_s, "84codes/site", "509", "csp-policy.json",
                                      chdir: directory.to_s)

      assert_predicate status, :success?
      [output.chomp, log.read]
    end
  end

  def fake_gh(bin, log, base_policy)
    bin.mkdir
    gh = bin.join("gh")
    gh.write(<<~SH)
      #!/bin/sh
      echo "$*" >> "#{log}"
      case "$1" in
        pr) echo base-sha ;;
        api) cat "#{base_policy}" 2>/dev/null || { echo '{"message":"Not Found"}'; exit 1; } ;;
      esac
    SH
    gh.chmod(0o755)
  end

  def test_compares_the_policy_with_the_base_branch_copy
    output, log = csp_changed(POLICY, POLICY)

    assert_equal "false", output
    assert_includes log, "pr view 509 --repo 84codes/site --json baseRefOid --jq .baseRefOid"
    assert_includes log, "repos/84codes/site/contents/csp-policy.json?ref=base-sha"
  end

  def test_treats_an_edited_policy_as_changed
    assert_equal "true", csp_changed(POLICY.sub("none", "self"), POLICY).first
  end

  def test_treats_a_policy_missing_on_the_base_branch_as_changed
    assert_equal "true", csp_changed(POLICY, nil).first
  end

  def test_skips_callers_without_a_policy_file
    output, log = csp_changed(nil, POLICY)

    assert_equal "false", output
    assert_empty log
  end
end
