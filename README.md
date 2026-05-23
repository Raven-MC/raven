# Arclight

Odin implementation of the Minecraft 1.8.x (protocol 47) server, with planned Bukkit/Paper plugin support via JNI.

## Building

```bash
odin run .       # build + run the server
odin build .     # build only
odin test src/protocol/   # run wire-format tests
```

The server reads `config.ini` from the current working directory. Without
it, the server falls back to `DEFAULT_SERVER` (`0.0.0.0:25565`).

## Useful links

- 1.8.x (protocol version 47) specification: [https://minecraft.wiki/w/Protocol?oldid=2772101](https://go.winlogon.org/9YiVvW) (Web Archive - archived from <https://minecraft.wiki/w/Protocol?oldid=2772100>)
- Encryption: <https://minecraft.wiki/w/Java_Edition_protocol/Encryption>
- Odin information: <https://odin-lang.org/docs/>
- Odin package search: <https://pkg.odin-lang.org/>
