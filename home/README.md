# Home Directory Files

Files in this directory are copied to the remote user's home directory during deployment.

The directory structure mirrors the home directory. For example:

```
home/
├── README.md           # This file (not copied)
├── .config/
│   └── git/
│       └── config      # → ~/.config/git/config
└── .local/
    └── bin/
        └── my-script   # → ~/.local/bin/my-script
```

## How it works

During `./deploy.sh`, the `setup_config()` function runs:

```bash
rsync -aq --exclude='README.md' "$script_dir/home/" "$TARGET_HOST:$remote_home/"
```

This copies everything except this README to the remote home directory.

## Notes

- Files are overwritten on each deploy
- For files managed by home-manager (like `.bashrc`), use `home.nix` instead
- For secrets, use `secrets.env` (copied to `~/.secrets.env`)
