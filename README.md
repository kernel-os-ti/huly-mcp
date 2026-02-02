# Huly MCP Server

> Model Context Protocol server for [Huly](https://huly.io) - Connect AI assistants to your Huly workspace

[![Swift 6.0+](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![MCP Protocol](https://img.shields.io/badge/MCP-1.0-blue.svg)](https://modelcontextprotocol.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Features

- ✅ **Project Management**: List and view projects
- ✅ **Issue Tracking**: Create, read, update, delete issues
- ✅ **Issue Operations**: Assign, comment, label issues
- ✅ **Document Management**: Manage documents in teamspaces
- ✅ **Team Collaboration**: List persons/contacts
- ✅ **Full-Text Search**: Search across workspace
- 🔒 **Secure**: Environment-based authentication
- ⚡ **Fast**: Swift-native with async/await

## Quick Start

### Prerequisites

- macOS 13.0+
- Swift 6.0+ ([install](https://swift.org/install))
- Huly instance access

### Installation

```bash
git clone https://github.com/yourusername/huly-mcp.git
cd huly-mcp
cp .env.example .env
# Edit .env with your credentials
swift build -c release
```

### Configuration

Edit `.env`:

```env
HULY_URL=https://your-huly-instance.com
HULY_EMAIL=your.email@example.com
HULY_PASSWORD=your-password
HULY_WORKSPACE=your-workspace-name
```

### Run

```bash
swift run huly-mcp
```

## MCP Tools

### Projects

#### `huly_list_projects`
List all projects in workspace.

**Example:**
```json
{"name": "huly_list_projects"}
```

#### `huly_get_project`
Get specific project.

**Parameters:**
- `identifier` (string, required): Project identifier (e.g., "PROJ")

### Issues

#### `huly_create_issue`
Create new issue.

**Parameters:**
- `project` (string, required): Project identifier
- `title` (string, required): Issue title (max 500 chars)
- `description` (string, optional): Description (max 10,000 chars)
- `priority` (integer, optional): 0=None, 1=Urgent, 2=High, 3=Medium, 4=Low

**Example:**
```json
{
  "name": "huly_create_issue",
  "arguments": {
    "project": "PROJ",
    "title": "Implement authentication",
    "priority": 2
  }
}
```

#### `huly_list_issues`
List issues, optionally filtered by project.

**Parameters:**
- `project` (string, optional): Project identifier filter
- `limit` (integer, optional): Max results (default: 50, max: 1000)

#### `huly_get_issue`
Get specific issue.

**Parameters:**
- `identifier` (string, required): Issue identifier (e.g., "PROJ-123")

#### `huly_update_issue`
Update existing issue.

**Parameters:**
- `identifier` (string, required): Issue identifier
- `title` (string, optional): New title
- `description` (string, optional): New description
- `priority` (integer, optional): New priority (0-4)
- `status` (string, optional): New status ID

#### `huly_delete_issue`
Delete issue.

**Parameters:**
- `identifier` (string, required): Issue identifier

#### `huly_assign_issue`
Assign issue to person.

**Parameters:**
- `identifier` (string, required): Issue identifier
- `person_id` (string, optional): Person ID (omit to unassign)

#### `huly_add_comment_to_issue`
Add comment to issue.

**Parameters:**
- `identifier` (string, required): Issue identifier
- `message` (string, required): Comment text

#### `huly_add_label_to_issue`
Add label/tag to issue.

**Parameters:**
- `identifier` (string, required): Issue identifier
- `label` (string, required): Label title
- `color` (integer, optional): Color index

### Documents

#### `huly_list_teamspaces`
List document teamspaces.

**Parameters:**
- `limit` (integer, optional): Max results (default: 50)

#### `huly_list_documents`
List documents.

**Parameters:**
- `teamspace` (string, optional): Filter by teamspace name
- `limit` (integer, optional): Max results (default: 50)

#### `huly_get_document`
Get specific document.

**Parameters:**
- `id` (string, required): Document ID

#### `huly_create_document`
Create new document.

**Parameters:**
- `teamspace` (string, required): Teamspace name
- `title` (string, required): Document title
- `content` (string, optional): Document content (markdown)

#### `huly_update_document`
Update existing document.

**Parameters:**
- `id` (string, required): Document ID
- `title` (string, optional): New title
- `content` (string, optional): New content

#### `huly_delete_document`
Delete document.

**Parameters:**
- `id` (string, required): Document ID

### Other

#### `huly_list_persons`
List persons/contacts.

**Parameters:**
- `limit` (integer, optional): Max results (default: 50)

#### `huly_search`
Full-text search across workspace.

**Parameters:**
- `query` (string, required): Search query
- `limit` (integer, optional): Max results (default: 20)

## Error Handling

All errors return structured JSON:

```json
{
  "error": {
    "code": "INVALID_INPUT",
    "message": "Title cannot be empty",
    "context": {
      "operation": "huly_create_issue"
    }
  }
}
```

**Error Codes:**
- `INVALID_INPUT`: Invalid parameters
- `AUTH_REQUIRED`: Not authenticated
- `AUTH_FAILED`: Authentication failed
- `NOT_FOUND`: Resource not found
- `REQUEST_FAILED`: API request failed
- `NETWORK_ERROR`: Network issue
- `CONFIG_ERROR`: Configuration error
- `DECODE_ERROR`: Failed to parse response

## Development

### Build

```bash
swift build
```

### Test

```bash
swift test
```

### Debug Mode

```bash
DEBUG=1 swift run huly-mcp
```

## Architecture

- `HulyClient.swift`: Core API client with authentication
- `Main.swift`: MCP server with tool handlers
- Uses Swift concurrency (async/await, actors)
- Validates all inputs before API calls
- Structured error responses

## License

MIT License - see [LICENSE](LICENSE).

## Support

- 🐛 Issues: [GitHub Issues](https://github.com/yourusername/huly-mcp/issues)
- 💬 Discussions: [GitHub Discussions](https://github.com/yourusername/huly-mcp/discussions)

## Acknowledgments

- Built with [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
- Powered by [Huly](https://huly.io)
