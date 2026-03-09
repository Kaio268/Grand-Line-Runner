local watcher = require(game:GetService("ServerScriptService").Modules.InventoryGearsWatcher)
watcher.Start()

local m = require(game:GetService("ServerScriptService").Modules.InventorySystemServer)
m.Start()
