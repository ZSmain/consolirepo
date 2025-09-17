#!/usr/bin/env -S v -raw-vsh-tmp-prefix tmp_generate_assets

// generate_assets_table.vsh - Generate release assets table and build cross-platform executables
import os
import flag

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
	mut fp := flag.new_flag_parser(os.args)
	fp.application('generate_assets_table')
	fp.description('Generate a Markdown downloads table for release assets and build cross-platform executables')

	// Asset table generation options
	dist := fp.string('dist', `d`, 'bin', 'Directory with built assets')
	tag := fp.string('tag', `t`, '', 'Release tag (e.g. v0.1.0) [required for table generation]')
	repo := fp.string('repo', `r`, '', 'owner/repo (e.g. ZSmain/consolirepo) [required for table generation]')

	// Build options
	build := fp.bool('build', `b`, false, 'Build cross-platform executables')
	source := fp.string('source', `s`, 'main.v', 'Source file to build')
	output_dir := fp.string('output', `o`, 'bin', 'Output directory for builds')

	fp.finalize() or {
		eprintln('Error: ${err}')
		exit(1)
	}

	// Generate assets table if requested
	if tag != '' && repo != '' {
		generate_assets_table(dist, tag, repo)!
	} else if !build {
		eprintln('Error: Either provide --tag and --repo for table generation, or use --build for cross-compilation')
		println(fp.usage())
		exit(1)
	}

	// Build cross-platform executables if requested
	if build {
		build_cross_platform(source, output_dir)!
	}
}

fn generate_assets_table(dist string, tag string, repo string) ! {
	println('🔍 Generating assets table for ${repo} v${tag}')

	if !os.exists(dist) {
		eprintln('Error: Directory ${dist} does not exist')
		exit(1)
	}

	files := os.ls(dist) or {
		eprintln('Could not read ${dist}: ${err}')
		exit(1)
	}

	mut rows := []AssetRow{}
	for name in files {
		path := os.join_path(dist, name)
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
		// sane default

		url := 'https://github.com/${repo}/releases/download/${tag}/${name}'
		rows << AssetRow{
			os:   pretty_os(os_name)
			arch: arch
			file: name
			url:  url
		}
	}

	if rows.len == 0 {
		println('⚠️  No asset files found in ${dist}')
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
	assets_file := os.join_path(dist, 'ASSETS.md')
	mut f := os.create(assets_file) or {
		eprintln('Could not create ${assets_file}: ${err}')
		return
	}
	defer { f.close() }

	f.writeln('# Release Assets - ${repo} v${tag}') or {
		eprintln('Could not write to ${assets_file}: ${err}')
		return
	}
	f.writeln('') or { return }
	f.writeln('| OS | Arch | Filename | Download |') or { return }
	f.writeln('| --- | --- | --- | --- |') or { return }
	for r in rows {
		f.writeln('| ${r.os} | ${r.arch} | ${r.file} | [Download](${r.url}) |') or {
			eprintln('Could not write to ${assets_file}: ${err}')
			return
		}
	}

	println('✅ Assets table saved to ${assets_file}')
}

fn build_cross_platform(source string, output_dir string) ! {
	println('🔨 Building cross-platform executables...')

	if !os.exists(source) {
		eprintln('Error: Source file ${source} does not exist')
		return
	}

	// Create output directory
	os.mkdir_all(output_dir) or {
		eprintln('Could not create output directory ${output_dir}: ${err}')
		return
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
		cmd := 'v -os ${target.os} -arch ${target.arch} -prod -o ${output_path} ${source}'
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

	if success_count > 0 {
		println('📁 Executables saved to: ${output_dir}')
		generate_assets_table(output_dir, 'latest', 'ZSmain/consolirepo')!
	}
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
