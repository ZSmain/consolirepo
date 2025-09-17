# Consolirepo

Convert a repository into a single text file for language model processing.

## Features

- Respects `.gitignore` patterns and excludes ignored files
- Detects and lists binary files separately (without including their content)
- Supports custom file extension filtering
- Automatically excludes common directories like `node_modules`, `.git`, `__pycache__`
- Generates date-stamped output filenames
- Fast native binary with no runtime dependencies

## Installation

Download the appropriate pre-built binary for your platform from the [releases page](https://github.com/ZSmain/consolirepo/releases):

- **Linux x86_64**: `consolirepo_linux_x86_64`
- **Linux ARM64**: `consolirepo_linux_arm64`
- **Windows x86_64**: `consolirepo_windows_x86_64.exe`
- **Windows ARM64**: `consolirepo_windows_arm64.exe`

Make the binary executable (Linux/macOS):

```bash
chmod +x consolirepo_linux_x86_64
```

## Usage

```bash
# Basic usage - process current directory
./consolirepo_linux_x86_64 --repo .

# Specify output file
./consolirepo_linux_x86_64 --repo /path/to/repo --output my_project.txt

# Filter by file extensions
./consolirepo_linux_x86_64 --repo . --ext .go,.rs,.py

# Show help
./consolirepo_linux_x86_64 --help
```

## Options

- `-r, --repo` - Path to repository (required)
- `-o, --output` - Output file path (default: `PROJECT_NAME_llm_YYYY-MM-DD.txt` where PROJECT_NAME is the base name of the repository)
- `-e, --ext` - Comma-separated extensions to include (e.g. `.go,.rs,.py`)

## Default Included Extensions

`.py`, `.js`, `.ts`, `.svelte`, `.txt`, `.md`, `.html`, `.css`, `.json`, `.yml`, `.yaml`, `.go`, `.rs`, `.c`, `.h`, `.cpp`, `.hpp`, `.java`, `.kt`, `.php`, `.rb`, `.sh`, `.bat`, `.ps1`, `.xml`, `.sql`, `.v`

## Output Format

The tool creates a text file with:

- Each source file prefixed with `## FILE: /path/to/file`
- File contents included directly
- Binary/media files listed at the end (without content)

### Example Output

```text
## FILE: main.v

module main

import os
// ... rest of file content ...

## FILE: README.md

# Consolirepo
// ... rest of file content ...

## BINARY/MEDIA FILES FOUND

The following binary/media files were found in the repository but not included in the content above:

- image.png
- video.mp4
```

Perfect for feeding entire codebases into language models for analysis, documentation, or code review.
