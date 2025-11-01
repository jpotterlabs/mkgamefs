# CRITICAL SAFETY RULES

## ⚠️ NEVER DELETE ANYTHING WITHOUT EXPLICIT PERMISSION

### Rule 1: No Deletions Without User Approval

**NEVER run commands that delete files or directories without explicit user permission**, including:
- `rm` 
- `rm -r`
- `rm -rf`
- `rmdir`
- Overwriting files with `>`
- Any destructive operations

### Rule 2: Check for Backups Before Any Destructive Operation

Before ANY operation that could result in data loss:
1. Ask the user if they want to proceed
2. Verify backups exist or warn that no backup exists
3. Get explicit confirmation

### Rule 3: Use Safe Alternatives

Instead of `rm -rf`, suggest:
- Moving to trash: `gio trash` or `mv to ~/.local/share/Trash`
- Renaming with timestamp: `mv file file.backup.$(date +%s)`
- Asking user to delete manually

### Rule 4: For Testing/Retries

When retrying a command that previously failed:
- **DO NOT** automatically delete the previous attempt
- Check if previous output exists
- Ask user: "Previous output exists at X. Delete and retry? (y/n)"
- Wait for explicit confirmation

### Examples of What NOT To Do

❌ **WRONG**:
```bash
rm -rf ~/TestPackages/Stellaris-Package && ./mkgamefs create ...
```

✅ **CORRECT**:
```bash
# Ask first
echo "Package exists at ~/TestPackages/Stellaris-Package"
echo "This will be overwritten. Continue? (y/n)"
# Or use --force flag and let user decide
./mkgamefs create ... --force
```

### Incident Log

**2024-10-26**: Accidentally deleted partially-complete Stellaris package (9.7GB DwarFS file) by running `rm -rf` before retry. This was the compressed result of 20 minutes of work.

**Lesson**: NEVER assume deletion is acceptable. Always ask first.

---

**This rule file must be read before ANY destructive operation.**
