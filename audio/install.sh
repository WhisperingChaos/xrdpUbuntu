#!/bin/bash
set -e

main(){
  if [ "$1" == "" ]; then
    main_install
    return
  fi
  if [ "$1" == "--verify" ]; then 
    main_clean
    return
  fi
  if [ "$1" == "--clean" ]; then 
    main_clean
    return
  fi
  main_unrecognized_option "$1"
  return 1
}

main_install(){
  pulse_version_check 
  read ttt
  pulse_source_get
  read ttt
  pulse_build_tools_get
  read ttt
  pulse_build_configure
  read ttt
  xrdp_sink_source_get
  read ttt
  xrdp_sink_compile
  read ttt
  xrdp_sink_install
  read ttt
  xrdp_sink_run_configure "$xrdp_SETTINGS_ALL_USERS"
}

main_verify(){
  pulse_loaded_xrdp 
}

main_clean(){
  xrdp_sink_clean
  pulse_clean
}

main_unrecognized_option(){
  cat >&2 <<MAIN_UNRECOGNIZE_OPTION

Error: Unrecongonized option: "$1".  Specify '--clean' to remove now unnecessary build components.
  + without options script attempts to install pulseaudio xrdp sink.
MAIN_UNRECOGNIZE_OPTION
}

declare -r pulse_DOWNLOAD_DIR="~/pulseaudio"
declare -r pulse_VERSION="11.1"
declare -r pulse_SOURCE_DIR="$pulse_DOWNLOAD_DIR-$pulse_VERSION"

pulse_version_check(){

  define -r pactl_VER_PATTERN='^pactl[[:space:]]+([0-9]\.[0-9])'
  pulse_VERSION="$(pactl --version)"
  [[ "$pulse_VERSION" =~ $pactl_VER_PATTERN ]]
  if [ "$BASH_REMATCH[1]" != "$pulse_VERSION" ]; then
    pulse_version_unexpected "$pulse_VERSION" "$BASH_REMATCH[1]"
    return 1
  fi
}

pulse_version_unexpected(){
  declare -r pulse_expected_ver="$1"
  declare -r pulse_actual_ver="$2"

  cat >&2 <<PULSE_VERSION_UNEXPECTED

Error: Script expects pulseaudio version: '$pulse_expected_ver' but encountered: '$pulse_actual_ver'.
PULSE_VERSION_UNEXPECTED
}

pulse_source_get(){
  mkdir -p "$pulse_DOWNLOAD_DIR"
  cd "$pulse_DOWNLOAD_DIR"
  sed -i 's/^# \(deb-src.* bionic main restricted\)/\1/' /etc/apt/sources.list
  apt update
  apt source pulseaudio
  sed -i 's/^\(deb-src.* bionic main restricted\)/# \1/' /etc/apt/sources.list
}

pulse_build_tools_get(){
  apt update
  apt build-dep -y pulseaudio
  apt install -y build-essential
  apt install -y dpkg-dev
  apt install -y libpulse-dev
}

pulse_build_tools_delete(){
  apt-mark auto $(apt-cache showsrc pulseaudio | grep Build-Depends | perl -p -e 's/(?:[[(].+?[])]|Build-Depends:|,||)//g')
  apt autoremove -y
  apt remove -y libpulse-dev
}

pulse_build_configure(){
  cd "$pulse_SOURCE_DIR"
  ./configure
}

declare -r xrdp_GIT_REPRO_NAME='pulseaudio-module-xrdp'
declare -r xrdp_GIT_REPRO_MASTER_VERSION='22d270b'
declare -r xrdp_SOURCE_DIR="$pulse_DOWNLOAD_DIR/$xrdp_GIT_REPRO_NAME"
declare -r xrdp_SINK_DIR="$xrdp_SOURCE_DIR/src/.libs/"

xrdp_sink_source_get(){
  mkdir -p "$xrdp_SOURCE_DIR"
  cd "$xrdp_SOURCE_DIR"
  wget https://github.com/neutrinolabs/pulseaudio-module-xrdp/tarball/$xrdp_GIT_REPRO_MASTER_VERSION
  cat "$xrdp_GIT_REPRO_MASTER_VERSION" | tar -xz --strip-component=1
}

xrdp_sink_source_delete(){
  dir_rm "$xrdp_SOURCE_DIR"
}

xrdp_sink_compile(){
  cd "$xrdp_SOURCE_DIR"
  ./bootstrap
  ./configure PULSE_DIR="$pulse_SOURCE_DIR"
  make
}

xrdp_sink_install(){
  cd "xrdp_SINK_DIR"
  install -t "/var/lib/xrdp-pulseaudio-installer" -D -m 644 *.so
}

#see: http://manpages.ubuntu.com/manpages/bionic/man5/default.pa.5.html
declare -r xrdp_SETTINGS_PER_USERS="~/.config/pulse/default.pa"
declare -r xrdp_SETTINGS_ALL_USERS="/etc/pulse/default.pa"
declare -r xrdp_SETTINGS_SYSTEM="/etc/pulse/system.pa"
declare -r xrdp_ORIGINAL_SUFFIX=".original"

pulse_xrdp_sink_run_configure(){
  declare -r setting_FILE="$1"

  pulse_xrdp_run_settings_preserve "$setting_FILE"
  pulse_xrdp_sink_run_settings     "$setting_FILE"
}

pulse_xrdp_run_settings_preserve(){
  declare -r setting_FILE="$1"

  declare -r setting_FILE_ORIGINAL="$setting_FILE$xrdp_ORIGINAL_SUFFIX"
  if [ -e "$setting_FILE_ORIGINAL" ]; then 
    pulse_xrdp_original_exists "$setting_FILE_ORIGINAL"
    return 1
  fi
  cp -a "$setting_FILE" "$setting_FILE_ORIGINAL"
}

pulse_xrdp_original_exists(){
  declare -r setting_FILE="$1"

  cat >&2 << PULSE_XRDP_ORIGINAL_EXISTS

Error: A backup of the original settings file already exists: "$setting_FILE".
  + It may contain pulseaudio settings you wish to preserve.  If not, delete this file
  + and try rerunning the script.
PULSE_XRDP_ORIGINAL_EXISTS
}

pulse_xrdp_sink_run_settings(){
  declare -r setting_FILE="$1"

  cat >"$setting_FILE" << XRDP_SINK_RUN_SETTINGS
.nofail
.fail
load-module module-augment-properties
load-module module-xrdp-sink
load-module module-native-protocol-unix
XRDP_SINK_RUN_SETTINGS
}

pulse_loaded_xrdp(){
  pactl --version >/dev/nul
  if ! pactl list sinks | grep "Name: xrdp-sink"; then
    pulse_loaded_xrdp_error
    return 1
  fi
}

pulse_loaded_xrdp_error(){
  cat >&2 <<PULSE_LOADED_XRDP_ERROR

Error: xrdp-sink not loaded by pulseaudio.
PULSE_LOADED_XRDP_ERROR
}

xrdp_sink_clean(){
  xrdp_sink_source_delete
}

pulse_clean(){
  pulse_sxrdp_original_delete
  pulse_source_delete
}

pulse_xrdp_original_delete(){
  declare -r setting_FILE="$1"

  declare -r setting_FILE_ORIGINAL="$setting_FILE$xrdp_ORIGINAL_SUFFIX"
  if ! [ -e "$setting_FILE_ORIGINAL" ]; then 
    # assumes first time the backup of original settings was properly
    # deleted and user running this script more than once.
    return
  fi
  rm "$setting_FILE_ORIGINAL" >/dev/nul
}

pulse_source_delete(){
  dir_rm "$pulse_SOURCE_DIR"
  dir_rm "$pulse_DOWNLOAD_DIR"
}

file_rm(){
  file_obj_rm "" "$1"
}

dir_rm(){
  file_obj_rm '-rf' "$1"
}

file_obj_rm(){
  declare -r target_FILE_OBJ="$2"

  if ! [ -e "$target_FILE_OBJ" ]; then
    # attempting to delete a non-existant file isn't an error
    return
  fi
  rm $target_FILE_OPTS "$target_FILE_OBJ" >/dev/nul
}







main

