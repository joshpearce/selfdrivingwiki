# signing/

Drop your downloaded macOS App Development provisioning profiles here:

- `WikiFS.provisionprofile`            (App ID org.sockpuppet.WikiFS)
- `WikiFSFileProvider.provisionprofile` (App ID org.sockpuppet.WikiFS.FileProvider)

`build.sh` embeds these into the app and `.appex` bundles at sign time
(wired up in Phase 2). They're machine/team-specific and **gitignored** —
re-download from developer.apple.com when they expire (~1 yr).

Full setup checklist: ../plans/signing.md
