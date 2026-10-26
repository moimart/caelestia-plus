# caelestia-plus defaults for fish: the prompt, abbreviations, tools. Fish
# loads this for every user, before ~/.config/fish/config.fish, so anything
# there wins. To skip these defaults: set -U caelestia_plus_no_defaults 1
if not set -q caelestia_plus_no_defaults; and test -f /usr/share/caelestia-plus/dots/fish/config.fish
    source /usr/share/caelestia-plus/dots/fish/config.fish
end
