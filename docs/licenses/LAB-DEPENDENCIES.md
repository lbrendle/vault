# Lab dependencies

Native Python/science artifacts and exact SHA-256 digests are recorded in `native/lab-dependencies.lock.json`. They are downloaded by `scripts/bootstrap-lab.py` and verified before extraction. Their bundled licence texts are retained under `lab/` and in package distribution metadata. CPython comes from BeeWare Python-Apple-support; native scientific wheels come from BeeWare; pure-Python wheels come from PyPI. Native MLX is already listed in the app notices.

The Mac environment is installed separately by its owner and is not bundled with the app.
