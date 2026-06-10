# Raven

Odin implementation of the Minecraft 1.8.x (protocol 47) server, with planned Bukkit/Paper plugin support via JNI.

> Named after Odin's ravens who flew across the world bringing information -- a server's role of connecting players to the Minecraft world.

## Building

```bash
odin run .       # build + run the server
odin build .     # build only
odin test src/protocol/   # run wire-format tests
```

The server reads `config.ini` from the current working directory. Without
it, the server falls back to `DEFAULT_SERVER` (`0.0.0.0:25565`).

## Useful links

- 1.8.x (protocol version 47) specification: <https://minecraft.wiki/w/Java_Edition_protocol/Packets?oldid=2772055> ([archived page](https://go.winlogon.org/9YiVvW))
- Encryption: <https://minecraft.wiki/w/Java_Edition_protocol/Encryption>

- Odin quick links:
  - Docs: <https://odin-lang.org/docs/>
  - Package search: <https://pkg.odin-lang.org/>
