export GROFF_ENCODING=UTF-8
export XDG_CACHE_HOME=/run/user/$(id -u)
export XDG_RUNTIME_HOME=/run/user/$(id -u)
chmod 700 /run/user/$(id -u)
mkdir -p $HOME/.ccache
