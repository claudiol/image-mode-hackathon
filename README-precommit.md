## Local Security Setup
To prevent accidentally committing API keys and secrets, it is highly encouraged to use `pre-commit`.

Please follow the following steps to ensure you have the tools installed locally
to make sure we don't include any secrets or API keys in our commits.

1. **Install pre-commit tool:**
   * Mac (Homebrew): `brew install pre-commit`
   * Python (pip): `pip install pre-commit`
   
2. **Install TruffleHog locally:**
   * Mac (Homebrew): `brew install trufflehog`
   * Other OS: See https://trufflesecurity.com/docs/pre-commit-hooks

3. **Activate the hook:**
   Run this in the root of the project directory:
   ```bash
   pre-commit install
