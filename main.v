module main

import os
import time
import cli
import regex
import strings

struct Runner {
mut:
	repo_root          string
	out_file           string
	include_ext        []string
	gitignore_patterns []string
	binary_files       []string
	files_included     int
	bytes_written      i64
}

const default_include_ext = ['.py', '.js', '.ts', '.svelte', '.txt', '.md', '.html', '.css', '.json',
	'.yml', '.yaml', '.go', '.rs', '.c', '.h', '.cpp', '.hpp', '.java', '.kt', '.php', '.rb', '.sh',
	'.bat', '.ps1', '.xml', '.sql', '.v']

const binary_extensions = [
	// Images
	'.jpg',
	'.jpeg',
	'.png',
	'.gif',
	'.bmp',
	'.tiff',
	'.webp',
	'.svg',
	'.ico',
	'.raw',
	// Videos
	'.mp4',
	'.avi',
	'.mov',
	'.wmv',
	'.flv',
	'.webm',
	'.mkv',
	'.m4v',
	// Audio
	'.mp3',
	'.wav',
	'.flac',
	'.aac',
	'.ogg',
	'.wma',
	'.m4a',
	// Documents
	'.pdf',
	'.doc',
	'.docx',
	'.xls',
	'.xlsx',
	'.ppt',
	'.pptx',
	// Archives
	'.zip',
	'.rar',
	'.7z',
	'.tar',
	'.gz',
	'.bz2',
	// Executables
	'.exe',
	'.dll',
	'.so',
	'.dylib',
]

const common_exclusions = ['.git', 'node_modules', '.venv', 'venv', 'env', '__pycache__',
	'.pytest_cache', '.DS_Store', 'Thumbs.db', 'pnpm-lock.yaml', 'bun.lock', 'yarn.lock', '*.min.js',
	'*.min.css', 'dist', 'build', 'target']

const max_file_size = 1 * 1024 * 1024 // 1MB limit for individual files

// Helper for tree sorting
struct TreeItem {
	name   string
	path   string
	is_dir bool
}

// new_runner creates a new Runner instance with the given parameters
fn new_runner(repo string, out string, include_extensions []string) Runner {
	final_include := if include_extensions.len > 0 {
		include_extensions.clone()
	} else {
		default_include_ext.clone()
	}

	return Runner{
		repo_root:          repo
		out_file:           out
		include_ext:        final_include
		gitignore_patterns: []string{}
		binary_files:       []string{}
		files_included:     0
		bytes_written:      0
	}
}

// parse_gitignore reads .gitignore file and parses patterns
// Handles basic gitignore syntax including directory patterns
fn (mut r Runner) parse_gitignore() {
	gitignore_path := os.join_path(r.repo_root, '.gitignore')
	mut patterns := []string{}

	if os.exists(gitignore_path) {
		content := os.read_file(gitignore_path) or { '' }
		for line in content.split_into_lines() {
			trimmed := line.trim_space()
			if trimmed != '' && !trimmed.starts_with('#') && !trimmed.starts_with('!') {
				// Remove leading slashes
				cleaned := trimmed.trim_string_left('/')
				patterns << cleaned
			}
		}
	}

	// Add common exclusions
	patterns << common_exclusions
	r.gitignore_patterns = patterns
}

// should_ignore_file checks if a file should be ignored based on gitignore patterns
fn (r &Runner) should_ignore_file(file_path string) bool {
	rel_path := file_path.replace(r.repo_root, '').trim_string_left('/')
	file_name := os.base(file_path)

	// Don't ignore our own output file
	if r.out_file != '' && file_path == r.out_file {
		return false
	}

	// Check each gitignore pattern
	for pattern in r.gitignore_patterns {
		if pattern.ends_with('/') {
			// Directory pattern
			dir_pattern := pattern.trim_string_right('/')
			if rel_path.starts_with(dir_pattern) || rel_path.contains('/' + dir_pattern) {
				return true
			}
		} else if pattern.contains('*') {
			// Simple wildcard matching
			if match_wildcard(pattern, rel_path) || match_wildcard(pattern, file_name) {
				return true
			}
		} else {
			// Exact match
			if rel_path == pattern || file_name == pattern {
				return true
			}
		}
	}
	return false
}

fn match_wildcard(pattern string, text string) bool {
	// Handle simple cases first
	if pattern == '*' {
		return true
	}
	if !pattern.contains('*') && !pattern.contains('?') {
		return pattern == text
	}

	// Convert wildcard pattern to regex using strings.Builder for efficiency
	mut sb := strings.new_builder(pattern.len * 2)
	for c in pattern {
		match c {
			`*` {
				sb.write_string('.*')
			}
			`?` {
				sb.write_u8(`.`)
			}
			`.` {
				sb.write_string('\\.')
			}
			`^`, `$`, `(`, `)`, `[`, `]`, `{`, `}`, `|`, `+`, `\\` {
				sb.write_u8(`\\`)
				sb.write_u8(c)
			}
			else {
				sb.write_string(c.ascii_str())
			}
		}
	}

	regex_pattern := sb.str()
	re := regex.regex_opt('^' + regex_pattern + '$') or {
		// Fallback to simple string matching for failed regex
		return text.contains(pattern.replace('*', ''))
	}

	return re.matches_string(text)
}

// walk_directory recursively traverses the directory tree and processes files
// It writes included file contents to the output file and collects binary files
fn (mut r Runner) walk_directory(root_path string, mut f os.File) ! {
	entries := os.ls(root_path) or { return }

	// Process files in this directory first
	for entry in entries {
		entry_path := os.join_path(root_path, entry)
		if os.is_file(entry_path) {
			// Skip if ignored by gitignore patterns
			if r.should_ignore_file(entry_path) {
				continue
			}

			ext := os.file_ext(entry).to_lower()

			// Check if it's a binary file
			if ext in binary_extensions {
				r.binary_files << entry_path
				continue
			}

			// Check if we should include this extension
			if ext in r.include_ext {
				// Check file size before reading
				file_size := os.file_size(entry_path)
				if file_size > max_file_size {
					eprintln('Skipping large file ${entry_path} (${file_size} bytes)')
					continue
				}

				content := os.read_file(entry_path) or {
					eprintln('Could not read ${entry_path}: ${err}')
					continue
				}

				// Write header and content
				f.write_string('## FILE: ${entry_path}\n\n')!
				f.write_string('${content}\n\n')!
				r.files_included++
				r.bytes_written += i64(content.len)
			}
		}
	}

	// Recursively process subdirectories
	for entry in entries {
		entry_path := os.join_path(root_path, entry)
		if os.is_dir(entry_path) {
			// Skip if ignored by gitignore patterns
			if !r.should_ignore_file(entry_path) {
				r.walk_directory(entry_path, mut f)!
			}
		}
	}
}

// Append directory tree at end of output
fn (r &Runner) append_dir_tree(mut f os.File) ! {
	f.write_string('\n\n## DIRECTORY TREE\n\n')!
	root_name := os.base(r.repo_root)
	f.write_string('${root_name}\n')!

	mut lines := []string{}
	r.build_dir_tree(r.repo_root, '', mut lines)!
	for line in lines {
		f.write_string('${line}\n')!
	}
}

fn (r &Runner) build_dir_tree(dir_path string, prefix string, mut lines []string) ! {
	entries := os.ls(dir_path) or { return }

	// Resolve absolute output path once to avoid including it in the tree
	mut out_abs := ''
	if r.out_file != '' {
		out_abs = os.real_path(r.out_file)
	}

	mut items := []TreeItem{}
	for name in entries {
		path := os.join_path(dir_path, name)

		// Skip the generated output file if it resides in the repo
		if out_abs != '' && os.real_path(path) == out_abs {
			continue
		}

		// Respect gitignore/common exclusions
		if r.should_ignore_file(path) {
			continue
		}

		items << TreeItem{
			name:   name
			path:   path
			is_dir: os.is_dir(path)
		}
	}

	// Sort: directories first, then files; alphabetical by name
	items.sort_with_compare(fn (a &TreeItem, b &TreeItem) int {
		if a.is_dir && !b.is_dir {
			return -1
		}
		if !a.is_dir && b.is_dir {
			return 1
		}
		if a.name < b.name {
			return -1
		}
		if a.name > b.name {
			return 1
		}
		return 0
	})

	for i, item in items {
		last := i == items.len - 1
		connector := if last { '└── ' } else { '├── ' }
		lines << prefix + connector + item.name
		if item.is_dir {
			new_prefix := prefix + if last { '    ' } else { '│   ' }
			r.build_dir_tree(item.path, new_prefix, mut lines)!
		}
	}
}

// process is the main processing function that orchestrates the repository consolidation
fn (mut r Runner) process() ! {
	println('Processing repository: ${r.repo_root}')

	// Parse .gitignore patterns
	r.parse_gitignore()

	// Generate default output filename if not provided
	mut out := r.out_file
	if out == '' {
		proj := os.base(r.repo_root)
		date_str := time.now().get_fmt_date_str(.hyphen, .yyyymmdd)
		out = '${proj}_llm_${date_str}.txt'
		r.out_file = out
	}

	println('Output file: ${out}')
	mut f := os.create(out)!
	defer {
		f.close()
	}

	// Walk repository
	r.walk_directory(r.repo_root, mut f)!

	// Add binary/media files section
	if r.binary_files.len > 0 {
		f.write_string('\n\n## BINARY/MEDIA FILES FOUND\n\n')!
		f.write_string('The following binary/media files were found in the repository but not included in the content above:\n\n')!
		r.binary_files.sort()
		for file_path in r.binary_files {
			f.write_string('- ${file_path}\n')!
		}
	}

	// Append directory tree for extra context
	r.append_dir_tree(mut f)!

	f.flush()
	println('Repository consolidation complete!')
	println('Files included: ${r.files_included}, Binary files listed: ${r.binary_files.len}, Bytes written: ${r.bytes_written}')
}

fn main() {
	mut app := cli.Command{
		name:        'consolirepo'
		description: 'Convert a repository into a single text file for language model processing'
		version:     '0.4.0'
		posix_mode:  true
		execute:     fn (cmd cli.Command) ! {
			// Get flag values
			repo := cmd.flags.get_string('repo')!
			output := cmd.flags.get_string('output') or { '' }
			extensions := cmd.flags.get_string('ext') or { '' }

			abs_repo := os.real_path(repo)
			if !os.exists(abs_repo) {
				return error('Error: ${abs_repo} does not exist')
			}
			if !os.is_dir(abs_repo) {
				return error('Error: ${abs_repo} is not a directory')
			}

			// Parse extensions if provided
			mut ext_list := []string{}
			if extensions != '' {
				ext_list = extensions.split(',').map(it.trim_space().to_lower())
			}

			mut runner := new_runner(abs_repo, output, ext_list)
			runner.process() or {
				return error('Processing failed: ${err}')
			}
		}
		flags: [
			cli.Flag{
				flag:        .string
				name:        'repo'
				abbrev:      'r'
				description: 'Path to the repository to process (required)'
				required:    true
			},
			cli.Flag{
				flag:        .string
				name:        'output'
				abbrev:      'o'
				description: 'Output file path (default: PROJECT_NAME_llm_YYYY-MM-DD.txt)'
			},
			cli.Flag{
				flag:        .string
				name:        'ext'
				abbrev:      'e'
				description: 'Comma-separated extensions to include (e.g. .go,.rs,.py)'
			}
		]
	}
	app.setup()
	app.parse(os.args)
}
