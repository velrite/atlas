# GitLab CI/CD Known Issues and Gotchas

## Entrypoint-based tool images require entrypoint override

Docker images such as aquasec/trivy and bridgecrew/checkov set the scanning tool itself as the container ENTRYPOINT. GitLab CI's default script execution wraps job scripts in a shell invocation, which becomes an extra "sh" argument passed directly to the tool binary when the entrypoint is not a shell, producing errors like unknown command "sh" for "trivy". The fix is to override the entrypoint in the job's image definition:

    image:
      name: aquasec/trivy:latest
      entrypoint: [""]

This applies to any tool image built this way, not just Trivy and Checkov.

## GitLab CI YAML linter is stricter than plain YAML validity

A .gitlab-ci.yml file can be valid YAML (confirmed with yaml.safe_load) and still be rejected by GitLab's own CI linter with an error such as script config should be a string or a nested array of strings. Certain punctuation combinations inside script string values, in this project's case parentheses combined with a comma-separated list, triggered this. The fix was to simplify the affected strings. When this occurs, GitLab's Pipeline Editor has a Validate function that identifies the exact offending job.

## GitLab CI/CD-only external repository connections are one-time imports, not live mirrors

Using "Run CI/CD for external repository" against a GitHub repo performs a one-time import. It does not automatically stay in sync with new commits unless a pull mirror is separately configured under Settings > Repository > Mirroring, and pull mirroring may not be available on all GitLab plans. Workaround used in this project: GitLab was added as a second git remote, and commits are pushed to both origin (GitHub) and gitlab (GitLab) after each commit.

## GitLab push authentication requires a Personal Access Token, not the account password

Git operations over HTTPS to gitlab.com require a Personal Access Token (fine-grained, scoped to the specific project, with Repository Code permission set to at least push and read), used as the password when prompted. The account password itself is rejected with an HTTP Basic access denied error.
