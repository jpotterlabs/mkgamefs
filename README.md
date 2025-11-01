# mkgamefs 🎮

**Version**: 1.0.0 (Bash Implementation)  
**Status**: ✅ Working - Core features complete and tested

**Game Filesystem Creator** - Package games into optimized DwarFS archives that can be **mounted and played without extraction**.

Inspired by [jc141's](https://github.com/jc141x) excellent game distribution system, completely rewritten in Bash for maximum compatibility and ease of use.

## 🎯 Key Feature: Play Without Extracting

Unlike traditional archives, mkgamefs packages let you:
- Mount games in **<1 second** (no extraction wait)
- Play directly from **40-60% compressed** archives  
- Save games via overlay filesystem (persistent)
- **Example**: 24GB Stellaris → 9.7GB package (61% savings)

---

## ✨ Features

### Core Capabilities
- 🔍 **Automatic game detection** - Identifies Windows/Native games, Unity/Unreal/Godot engines, and main executables
- 🍷 **Full Wine/Proton support** - Auto-detects and configures Wine or Proton runtimes
- 🌋 **Vulkan management** - Detects or auto-downloads DXVK and VKD3D-Proton
- 🗜️ **Optimized compression** - 64MB blocks, nilsimsa ordering, 40-60% space savings
- 📦 **jc141-compatible packages** - Uses same directory structure and launcher system
- 🔒 **Sandboxing support** - Optional bubblewrap isolation
- 🎨 **Beautiful CLI** - Colored output with progress indicators

### Supported Game Types
- **Windows games** (via Wine/Proton)
- **Native Linux games**
- **Unity, Unreal, Godot, Source, GameMaker, RPG Maker engines**

---

## 🚀 Quick Start

### Prerequisites

```bash
# Required packages
sudo apt install dwarfs fuse-overlayfs psmisc file

# Optional (for Wine games)
sudo apt install wine bubblewrap vulkan-tools zstd

# For downloading Vulkan components
sudo apt install curl tar
```

**Alternative:** If `dwarfs` package is not available in your repos, download the universal binary:
```bash
# Download from GitHub releases
wget https://github.com/mhx/dwarfs/releases/download/v0.14.1/dwarfs-0.14.1-Linux-x86_64.tar.xz
tar xf dwarfs-0.14.1-Linux-x86_64.tar.xz
sudo cp dwarfs-*/bin/* /usr/local/bin/
```

### Installation

```bash
# Navigate to mkgamefs directory
cd /home/jason/Projects/dwarfs/tools/mkgamefs

# Already executable, test it
./mkgamefs --help

# Optional: Add to PATH
sudo ln -s $(pwd)/mkgamefs /usr/local/bin/mkgamefs
```

### Basic Usage

```bash
# Create a game package
mkgamefs create -i ~/Games/MyGame -o MyGame-Package

# Launch the game
cd MyGame-Package && ./start.sh

# Extract if needed
mkgamefs extract -i MyGame-Package -o ~/Games/MyGame-Extracted

# Test package integrity
mkgamefs test MyGame-Package

# Show package info
mkgamefs info MyGame-Package
```

---

## 📖 Commands

### `create` - Create a Game Package

Package a game directory into an optimized DwarFS archive with launchers.

```bash
mkgamefs create -i <INPUT> -o <OUTPUT> [OPTIONS]
```

**Options:**
- `-i, --input DIR` - Input game directory (required)
- `-o, --output DIR` - Output package directory (required)
- `-n, --name NAME` - Game name (defaults to directory name)
- `-r, --runtime TYPE` - Runtime: `auto`, `wine`, `proton`, `native` (default: `auto`)
- `-l, --level LEVEL` - Compression level 0-9 (default: 7)
- `-f, --force` - Overwrite existing package
- `--no-categorize` - Disable file categorization
- `--no-vulkan` - Don't download Vulkan components
- `-h, --help` - Show help

**Examples:**

```bash
# Auto-detect everything
mkgamefs create -i ~/Games/Factorio -o Factorio-Package

# Windows game with Wine
mkgamefs create -i ~/Games/Cyberpunk2077 -o Cyberpunk --runtime wine

# Max compression for smaller games
mkgamefs create -i ~/Games/IndieGame -o IndieGame -l 9

# Force overwrite existing package
mkgamefs create -i ~/Games/Game -o Game-Package -f
```

**What it does:**
1. Analyzes game (type, engine, executable)
2. Configures runtime (Wine/Proton detection)
3. Downloads Vulkan components if needed
4. Compresses game to DwarFS (50-60% savings)
5. Generates launcher scripts
6. Creates complete, runnable package

---

## 📁 Package Structure

```
GamePackage/
├── files/
│   ├── game-root.dwarfs       # Compressed game (50-60% of original)
│   ├── overlay-storage/       # Persistent changes (saves, configs)
│   └── vulkan.tar.xz          # Bundled Vulkan (if needed)
├── actions.sh                  # Helper functions (mount/unmount/extract)
├── start.sh                    # Main launcher
└── script_default_settings     # Configuration file
```

**Note:** For maximum portability, you can bundle the `dwarfs-universal-extract` binary from the DwarFS releases. This allows packages to work on systems without DwarFS installed. However, this is not required for basic functionality.

### How It Works

1. **DwarFS Archive** - Game files compressed with 64MB blocks, nilsimsa ordering
2. **Overlay Filesystem** - fuse-overlayfs provides writable layer for saves
3. **Smart Caching** - 25% RAM used for fast file access
4. **Auto-cleanup** - Unmounts after game exits

---

## 🍷 Wine/Proton Integration

### Automatic Detection

mkgamefs automatically:
- Detects if game is Windows (`.exe`, `.dll` files)
- Finds system Wine or Proton installations
- Prefers Proton-GE > Proton > Wine
- Configures Wine prefix with optimal settings

### Vulkan Components

For Windows games, mkgamefs:
- Checks for system DXVK and VKD3D-Proton
- Downloads missing components automatically
- Bundles them in package or uses system versions
- Installs to Wine prefix on first launch

---

## ⚙️ Configuration

### Global Config: `~/.jc141rc`

```bash
# Automatically generated on first run
UNMOUNT=1              # Auto-unmount after game exits
EXTRACT=0              # Mount (0) or extract (1) on launch
TERMINAL_OUTPUT=1      # Show output
ISOLATE=1              # Use bubblewrap sandboxing
BLOCK_NET=1            # Block network in sandbox
GAMESCOPE=0            # Use gamescope compositor
JC_DIRECTORY="$HOME/Games/jc141"  # Prefix/save location
```

### Per-Game Config: `script_default_settings`

Located in each package directory. Overrides global settings.

---

## 🐛 Troubleshooting

### "Missing dependencies"

```bash
# Install all required and optional packages
sudo apt install dwarfs fuse-overlayfs psmisc file wine bubblewrap vulkan-tools zstd curl

# Or minimal (no Wine support)
sudo apt install dwarfs fuse-overlayfs psmisc file
```

### "Failed to mount"

```bash
# Check if already mounted
fusermount3 -u ~/path/to/package/files/game-root
```

### "Game won't launch"

```bash
# Test package
mkgamefs test package/

# Debug
cd package/ && bash -x start.sh
```

---

## 📊 Comparison: mkgamefs vs jc141

| Feature | mkgamefs | jc141 |
|---------|----------|-------|
| **Creation** | Automated CLI tool | Manual setup |
| **Detection** | Auto-detect game type | Manual config |
| **Wine/Proton** | Auto-detect both | Wine only |
| **Vulkan** | Auto-download | Manual install |
| **Testing** | Built-in test suite | None |
| **Launchers** | Auto-generated | Pre-made |

---

## 🙏 Credits

- **jc141** - For pioneering DwarFS-based game distribution
- **mhx** - For creating DwarFS
- **GloriousEggroll** - For Proton-GE
- **doitsujin** - For DXVK
- **HansKristian-Work** - For VKD3D-Proton

---

**Version**: 1.0.0  
**Status**: Production Ready ✅  
**Bash**: 4.0+
