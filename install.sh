#!/bin/bash
set -e

main(){
  install_core
  polkit_rules_update
  firewall_xrdp_allow
  xrdp_restart
  xrdp_status
}

install_core(){
  apt get update
  apt install -y  xrdp
  apt-get install -y xserver-xorg-core
  apt-get install -y xorgxrdp
}

polkit_rules_update() {
  polkit_rules > /etc/polkit-1/localauthority.conf.d/02-allow-colord.conf
}

polkit_rules() {
cat <<POLKIT_RULES
polkit.addRule(function(action, subject) {
if ((action.id == “org.freedesktop.color-manager.create-device” || action.id == “org.freedesktop.color-manager.create-profile” || action.id == “org.freedesktop.color-manager.delete-device” || action.id == “org.freedesktop.color-manager.delete-profile” || action.id == “org.freedesktop.color-manager.modify-device” || action.id == “org.freedesktop.color-manager.modify-profile”) && subject.isInGroup(“{group}”))
{
return polkit.Result.YES;
}
});
POLKIT_RULES
}

firewall_xrdp_update(){
  ufw allow 3389/tcp
}
 
xrdp_restart(){
  /etc/init.d/xrdp restart
}

xrdp_status(){
  systemctl status xrdp
}
main
