local Types = {}

local ProfileStore = require(game.ServerScriptService.Framework.ProfileStore)

export type DataManager = {
	AddValue : (self: any, player: Player, path: string, addValue: (number | {any?})) -> (),
	AddBrainrot : (self: any, player: Player, BrainrotName: string, Amount: (number | {any?})) -> (),
	StartBoost : (self: any, player: Player, boostName: string, timePerUnit: number, amountUsed: (number | {any?})) -> (),


	AddAttribute : (self: any, player: Player, path: string, attributes:  (string) | {any?}) -> (),
	GetBackup : (self: any , userI : number, sort_direction: Enum.SortDirection?,  min_date: DateTime?, max_date: DateTime?) -> (),
	GetData : (self: any, player: Player) -> (),
	GetProfile : (self: any, player: Player) -> (),
	GetReplica : (self: any, player: Player) -> (),
	GetValue : (self: any, player: Player, path: string) -> (),
	Leaderstats : (self: any, player: Player) -> (),
	LoadBackup : (self: any, profile: {any}) -> (),
	HardResetData : (self: any, userId: number, kickMessage: string?) -> (boolean, string?),
	IsHardResetPending : (self: any, userId: number) -> boolean,
	MessageAsync : (self: any, userId: number, message: {any?}) -> boolean,
	PromptProductPurchase : (self: any, player: Player, productId: number) -> (),
	ResetData : (self: any, userId: number) -> boolean,
	SetValue : (self: any, player: Player, path: string, newValue: (string | number | boolean | {any?})?) -> (),
	SubValue : (self: any, player: Player, path: string, subValue: (number | {any?})) -> (),
	Version : (self: any) -> typeof(print()),
	GetAllPlayers : (self: any) -> {[number]: typeof(os.time())}
}

return Types
