LANG=C gsettings get org.mate.control-center.keybinding:/org/mate/desktop/keybindings/custom0/ action
'/opt/I38/scripts/toggle_screenreader.sh'

On peut créer des schémas dérivés d'un schéma réadressable:
LANG=C gsettings list-keys org.mate.control-center.keybinding:/org/mate/desktop/keybindings/custom1/
action
name
binding
