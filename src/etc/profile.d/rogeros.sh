# Prompt neón y bienvenida
if [ -n "$BASH_VERSION" ] && [ -n "$PS1" ]; then
  PS1='\[\e[1;96m\]\u\[\e[1;95m\]@rogeros \[\e[1;94m\]\w \[\e[1;95m\]❯\[\e[0m\] '
  command -v fastfetch >/dev/null && [ -z "$ROGEROS_HOLA" ] && export ROGEROS_HOLA=1 && fastfetch
fi
