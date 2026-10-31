# Determinate optimizes fetches carrying revCount into shallow clones even when
# shallow=false. Keep the locked revision and hash, but omit that optimization hint.
locked: builtins.fetchTree ((builtins.removeAttrs locked [ "revCount" ]) // { shallow = false; })
