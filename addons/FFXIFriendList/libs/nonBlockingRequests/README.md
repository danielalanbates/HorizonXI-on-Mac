# nonBlockingRequests Module

This directory contains the `nonBlockingRequests` module from:
**https://github.com/loonsies/nonBlockingRequests**

## Setup

This module should be added as a Git submodule:

```bash
git submodule add https://github.com/loonsies/nonBlockingRequests.git libs/nonBlockingRequests
```

Or if the submodule already exists:

```bash
git submodule update --init --recursive
```

## Current Status

✅ Module is installed and ready to use.

The module requires LuaSocket dependencies (`socket`, `socket.url`, `socket.ssl`) which should be available in Ashita v4.

## Usage

The module is used by `libs/net.lua` which provides the app feature API:

```lua
local http = require("libs.nonBlockingRequests.nonBlockingRequests")

-- In d3d_present callback (called via libs/net.lua):
http.processAll()

-- GET request
http.get(url, headers, function(body, err, status)
    -- Handle response
end)

-- POST request
http.post(url, body, headers, function(body, err, status)
    -- Handle response
end)
```

## Module API

- `http.get(url, headers, callback)` - GET request
- `http.post(url, body, headers, callback)` - POST request
- `http.processAll()` - Call every frame in d3d_present
- `http.cancel(requestId)` - Cancel a request
- `http.getActiveCount()` - Get number of active requests

**Callback signature**: `function(body, err, status)`

## Integration

The module is wrapped by `libs/net.lua` which:
- Enforces max 4-8 in-flight requests
- Provides request queue management
- Converts callback format to match app feature expectations
- Handles request cancellation and cleanup

