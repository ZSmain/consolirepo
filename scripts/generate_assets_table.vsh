#!/usr/bin/env -S v -raw-vsh-tmp-prefix tmp_generate_assets

// generate_assets_table.vsh - Build consolirepo executables and generate release assets table
import os
import cli

// Hardcoded constants for this specific application
const repo = 'ZSmain/consolirepo'
const source_file = 'main.v'
const output_dir = 'bin'

struct AssetRow {
	os   string
	arch string
	file string
	url  string
}

struct BuildTarget {
	os   string
	arch string
	ext  string
}

fn main() {
	mut app := cli.Command{
		name:        'generate_assets_table'
		description: 'Build consolirepo executables and generate release assets table'
		posix_mode:  true
		execute:     fn (cmd cli.Command) ! {
			// Get tag (required)
			tag := cmd.flags.get_string('tag')!
			
			println('🚀 Building consolirepo release ${tag}')
			
			// Always build first
			build_cross_platform()!
			
			// Then generate assets table
			generate_assets_table(tag)!
		}
		flags: [
			cli.Flag{
				flag:        .string
				name:        'tag'
				abbrev:      't'
				description: 'Release tag (e.g. v0.3.0)'
				required:    true
			}
		]
	}
	app.setup()
	app.parse(os.args)
}

fn generate_assets_table(tag string) ! {
	println('🔍 Generating assets table for ${repo} ${tag}')

	if !os.exists(output_dir) {
		return error('Directory ${output_dir} does not exist')
	}

	files := os.ls(output_dir) or {
		return error('Could not read ${output_dir}: ${err}')
	}

	mut rows := []AssetRow{}
	for name in files {
		path := os.join_path(output_dir, name)
		if os.is_dir(path) {
			continue
		}

		// Skip the generated table and checksum files
		if name == 'ASSETS.md' || name == 'SHA256SUMS' || name == 'generate_assets_table' {
			continue
		}

		mut os_name := infer_os(name)
		mut arch := infer_arch(name)
		if os_name == '' {
			os_name = infer_os_by_ext(name)
		}
		if arch == '' {
			arch = 'x86_64'
		}

		url := 'https://github.com/${repo}/releases/download/${tag}/${name}'
		rows << AssetRow{
			os:   pretty_os(os_name)
			arch: arch
			file: name
			url:  url
		}
	}

	if rows.len == 0 {
		println('⚠️  No asset files found in ${output_dir}')
		return
	}

	// Sort by OS then arch
	rows.sort_with_compare(fn (a &AssetRow, b &AssetRow) int {
		if a.os == b.os {
			return a.arch.compare(b.arch)
		}
		return a.os.compare(b.os)
	})

	// Print table
	println('\n📋 Release Assets Table:')
	println('| OS | Arch | Filename | Download |')
	println('| --- | --- | --- | --- |')
	for r in rows {
		println('| ${r.os} | ${r.arch} | ${r.file} | [Download](${r.url}) |')
	}

	// Save to file
	assets_file := os.join_path(output_dir, 'ASSETS.md')
	mut f := os.create(assets_file) or {
		return error('Could not create ${assets_file}: ${err}')
	}
	defer { f.close() }

	f.writeln('# Release Assets - ${repo} ${tag}') or {
		return error('Could not write to ${assets_file}: ${err}')
	}
	f.writeln('') or { return }
	f.writeln('| OS | Arch | Filename | Download |') or { return }
	f.writeln('| --- | --- | --- | --- |') or { return }
	for r in rows {
		f.writeln('| ${r.os} | ${r.arch} | ${r.file} | [Download](${r.url}) |') or {
			return error('Could not write to ${assets_file}: ${err}')
		}
	}

	println('✅ Assets table saved to ${assets_file}')
}

fn build_cross_platform() ! {
	println('🔨 Building cross-platform executables...')

	if !os.exists(source_file) {
		return error('Source file ${source_file} does not exist')
	}

	// Create output directory
	os.mkdir_all(output_dir) or {
		return error('Could not create output directory ${output_dir}: ${err}')
	}

	// Define build targets - Linux and Windows only
	targets := [
		BuildTarget{
			os:   'linux'
			arch: 'x86_64'
			ext:  ''
		},
		BuildTarget{
			os:   'linux'
			arch: 'arm64'
			ext:  ''
		},
		BuildTarget{
			os:   'windows'
			arch: 'x86_64'
			ext:  '.exe'
		},
		BuildTarget{
			os:   'windows'
			arch: 'arm64'
			ext:  '.exe'
		},
	]

	base_name := 'consolirepo'
	mut success_count := 0

	for target in targets {
		output_name := '${base_name}_${target.os}_${target.arch}${target.ext}'
		output_path := os.join_path(output_dir, output_name)

		println('  Building ${target.os}/${target.arch}...')

		// Cross-compilation for Linux/Windows
		cmd := 'v -os ${target.os} -arch ${target.arch} -prod -o ${output_path} ${source_file}'
		result := os.execute(cmd)
		build_success := result.exit_code == 0

		if build_success {
			println('    ✅ ${output_name}')
			success_count++
		} else {
			println('    ❌ Failed to build ${target.os}/${target.arch}: ${result.output}')
		}
	}

	println('\n📊 Build Summary: ${success_count}/${targets.len} targets successful')

	if success_count == 0 {
		return error('All builds failed')
	}

	println('📁 Executables saved to: ${output_dir}')
}

fn infer_os(name string) string {
	l := name.to_lower()
	if l.contains('linux') {
		return 'linux'
	}
	if l.contains('windows') {
		return 'windows'
	}
	return ''
}

fn infer_os_by_ext(name string) string {
	l := name.to_lower()
	if l.ends_with('.exe') {
		return 'windows'
	}
	// If there's no extension at all, assume Linux (common for ELF binaries)
	if !l.contains('.') {
		return 'linux'
	}
	return ''
}

fn infer_arch(name string) string {
	l := name.to_lower()
	if l.contains('x86_64') || l.contains('amd64') {
		return 'x86_64'
	}
	if l.contains('arm64') || l.contains('aarch64') {
		return 'arm64'
	}
	if l.contains('armv7') {
		return 'armv7'
	}
	if l.contains('armhf') {
		return 'armhf'
	}
	if l.contains('ppc64le') {
		return 'ppc64le'
	}
	if l.contains('s390x') {
		return 's390x'
	}
	return ''
}

fn pretty_os(os_name string) string {
	return match os_name.to_lower() {
		'windows' { 'Windows' }
		'linux' { 'Linux' }
		else { os_name }
	}
}
