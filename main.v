module main

import os
import time
import flag
import regex

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
	
	// Convert wildcard pattern to regex
	mut regex_pattern := ''
	for c in pattern {
		match c {
			`*` {
				regex_pattern += '.*'
			}
			`?` {
				regex_pattern += '.'
			}
			`.` {
				regex_pattern += '\\.'
			}
			`^`, `$`, `(`, `)`, `[`, `]`, `{`, `}`, `|`, `+`, `\\` {
				regex_pattern += '\\${c}'
			}
			else {
				regex_pattern += c.ascii_str()
			}
		}
	}
	
	re := regex.regex_opt('^' + regex_pattern + '$') or { 
		// Fallback to simple string matching for failed regex
		return text.contains(pattern.replace('*', ''))
	}
	return re.matches_string(text)
}

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

	f.flush()
	println('Repository consolidation complete!')
	println('Files included: ${r.files_included}, Binary files listed: ${r.binary_files.len}, Bytes written: ${r.bytes_written}')
}

fn main() {
	mut fp := flag.new_flag_parser(os.args)
	fp.application('consolirepo')
	fp.description('Convert a repository into a single text file for language model processing')
	fp.version('0.1.0')

	repo := fp.string('repo', `r`, '', 'Path to the repository to process (required)')
	out := fp.string('output', `o`, '', 'Output file path (default: PROJECT_NAME_llm_YYYY-MM-DD.txt)')
	extensions := fp.string('ext', `e`, '', 'Comma-separated extensions to include (e.g. .go,.rs,.py)')

	fp.finalize() or {
		eprintln('Error: ${err}')
		println(fp.usage())
		return
	}

	if repo == '' {
		eprintln('Error: -repo is required')
		println(fp.usage())
		return
	}

	abs_repo := os.real_path(repo)
	if !os.exists(abs_repo) || !os.is_dir(abs_repo) {
		eprintln('Error: ${abs_repo} is not a valid directory')
		return
	}

	// Parse extensions if provided
	mut ext_list := []string{}
	if extensions != '' {
		ext_list = extensions.split(',').map(it.trim_space())
	}

	mut runner := new_runner(abs_repo, out, ext_list)
	runner.process() or { eprintln('Error: ${err}') }
}
