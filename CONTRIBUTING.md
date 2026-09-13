# Contributing

Thanks for helping make a thoughtful, private document workspace.

1. Open an issue for a substantial behavior or architecture change. Explain the user problem and a small example.
2. Fork the repository and create a branch. Follow [the build guide](docs/BUILDING.md).
3. Keep changes focused. Add a regression test for data loss, sync, parsing, download integrity, or model behavior changes. Use synthetic files only.
4. Run `npm test --prefix web`, `npm run build --prefix web`, `swift test -j 2`, and `python3 -m unittest discover -s scripts/tests -v`. Build both native targets when changing app code.
5. Explain the problem, resulting behavior, tests, and remaining limits in the pull request. Include a screenshot for visible UI changes, with fictional data.

Keep desktop, phone, tablet, keyboard, touch, reduced-motion, light, and dark behavior in mind. Never couple the app to one person's folders, hardware budget, credentials, model cache, or external services. Preserve user files and unrelated processes. Model files are data; do not add remote model-code execution.

Do not commit weights, generated builds, user documents, keys, pairing material, provisioning profiles, or private test logs. Run `gitleaks dir . --redact` on the intended public files before opening a PR. Dependency versions belong in lockfiles. License and attribution changes must accompany new distributed dependencies or assets.

By submitting a contribution, you agree it can be distributed under this project's Apache-2.0 license. You must have the right to contribute it. AI-assisted work is welcome under the same review and testing requirements; describe material generated assets or code when it helps reviewers establish provenance. No separate contributor license agreement is currently required.
