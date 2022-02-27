#!/bin/sh
# SPDX-License-Identifier: MIT

usage() {
	cat >&2 <<EOH
Usage: $0 <volume> <script> [--icon <icon file>] [--app-name <app name>] \
[--app-title <app title>]

Creates the necessary files on a USB disk or APFS volume so it will appear on
the Mac’s boot menu and run the specified script when selected. This generates
a fake macOS installer application which will run the shell script in the
recovery environment’s Terminal.
    <volume>: Destination volume.
    <script>: Script which will be run.
    <icon file>: Icon file (.icns) to use on the fake application. Will be
        visible in the Finder and the recovery environment’s main menu (shown
        when exiting the Terminal).
    <app name>: Internal name to use on the fake application. Not visible to
        the user. Defaults to "SomeApp".
    <app title>: Title to use on the fake application. Will be visible in the
        Finder and the recovery environment’s main menu. Defaults to "Some App".
EOH

	exit 1
}

error() {
	echo "$@" >&2
	exit 1
}

volume=""
script_file=""
icon=""
app_name="SomeApp"
app_title="Some App"

while [ -n "$1" ]; do
	case "$1" in
		--icon)
			{ [ -n "$2" ] && [ -z "$icon" ]; } || usage
			icon="$2"
			shift
		;;
		--app-name)
			[ -n "$2" ] || usage
			app_name="$2"
			shift
		;;
		--app-title)
			[ -n "$2" ] || usage
			app_title="$2"
			shift
		;;
		-*)
			usage
		;;
		?*)
			if [ -z "$volume" ]; then
				volume="$1"
			elif [ -z "$script_file" ]; then
				script_file="$1"
			else
				usage
			fi
		;;
		*)
			usage
		;;
	esac
	shift
done

[ -n "$volume" ] || usage
[ -n "$script_file" ] || usage

[ -d "$volume" ] || error "${volume} is not a directory."
[ -f "$script_file" ] || error "${script_file} is not a file."
[ -z "$icon" ] || [ -f "$icon" ] || error "${icon} is not an icon file."

set -e

app_path="${volume}/${app_title}.app"
app_res="${app_path}/Contents/Resources"
echo "Creating fake application ${app_path}"

rm -rf "${app_path}"
mkdir -p "${app_path}"

# Create the InfoPlist.strings file
mkdir -p "${app_res}/en.lproj"
cat > "${app_res}/en.lproj/InfoPlist.strings" <<EOF
"CFBundleDisplayName" = "${app_title}";
EOF


# Create the app Info.plist and the icon, if specified
if [ -z "$icon" ]; then
	cat > "${app_path}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>${app_title}</string>
	<key>CFBundleExecutable</key>
	<string>${app_name}</string>
</dict>
</plist>
EOF
else
	cp "$icon" "${app_path}/Contents/Resources/${app_name}.icns"
	cat > "${app_path}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>${app_title}</string>
	<key>CFBundleExecutable</key>
	<string>${app_name}</string>
	<key>CFBundleIconFile</key>
	<string>${app_name}</string>
</dict>
</plist>
EOF
fi

# Create the app executable and the command script
app_exec_dir="${app_path}/Contents/MacOS"
app_exec="${app_exec_dir}/${app_name}"
script_base="${script_file##*/}"
cmd_script_name="${script_base%.*}.command"

mkdir "$app_exec_dir"
cat > "${app_exec}" <<EOF
#!/bin/bash
exec /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal \
"\${0%/*}/../Resources/${cmd_script_name}"
EOF
chmod a+x "${app_exec}"

cp "${script_file}" "${app_res}/${cmd_script_name}"

boot_menu_info_path="${volume}/.IAPhysicalMedia"
echo "Creating boot menu file ${boot_menu_info_path}"

# ProductBuildVersion can apparently be any value, but must be present.
# ProductVersion must be a version number (with optional minor/micro), >= 11.3
cat > "$boot_menu_info_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AppName</key>
	<string>${app_title}.app</string>
	<key>ProductBuildVersion</key>
	<string></string>
	<key>ProductVersion</key>
	<string>99</string>
</dict>
</plist>
EOF

echo "Done!"
