## Kong Konnect MCP Server

A docker image for runnning [Kong Konnect MCP server](https://github.com/Kong/mcp-konnect). To use it with [Claude desktop](https://claude.ai/download), add below to `claude_desktop_config.json`. 

```json
{
  "mcpServers": {
    "kong-konnect": {
      "command": "docker",
      "args": [
        "run",
        "-i",
        "--init",
        "--rm",
        "-e",
        "KONNECT_ACCESS_TOKEN",
        "-e",
        "KONNECT_REGION",
        "fomm/mcp-konnect"
      ],
      "env": {
        "KONNECT_ACCESS_TOKEN": "<YOUR SYSTEM ACCOUNT TOKEN>",
        "KONNECT_REGION": "<YOUR REGION>"
      }
    }
  }
}
```