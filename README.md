# Consolirepo

Convert a repository into a single text file for language model processing.

## Features

- Respects `.gitignore` patterns and excludes ignored files
- Detects and lists binary files separately (without including their content)
- Supports custom file extension filtering
- Automatically excludes common directories like `node_modules`, `.git`, `__pycache__`
- Generates date-stamped output filenames
- Fast native V binary with no dependencies

## Installation

```bash
# Build the binary
v -prod -o consolirepo main.v

# Or run directly
v run main.v
```

## Usage

```bash
# Basic usage - process current directory
./consolirepo --repo .

# Specify output file
./consolirepo --repo /path/to/repo --output my_project.txt

# Filter by file extensions
./consolirepo --repo . --ext .go,.rs,.py

# Show help
./consolirepo --help
```

## Options

- `-r, --repo` - Path to repository (required)
- `-o, --output` - Output file path (default: `PROJECT_NAME_llm_YYYY-MM-DD.txt`)  
- `-e, --ext` - Comma-separated extensions to include (e.g. `.go,.rs,.py`)

## Default Included Extensions

`.py`, `.js`, `.ts`, `.svelte`, `.txt`, `.md`, `.html`, `.css`, `.json`, `.yml`, `.yaml`, `.go`, `.rs`, `.c`, `.h`, `.cpp`, `.hpp`, `.java`, `.kt`, `.php`, `.rb`, `.sh`, `.bat`, `.ps1`, `.xml`, `.sql`, `.v`

## Output Format

The tool creates a text file with:

- Each source file prefixed with `## FILE: /path/to/file`
- File contents included directly
- Binary/media files listed at the end (without content)

Perfect for feeding entire codebases into language models for analysis, documentation, or code review.
