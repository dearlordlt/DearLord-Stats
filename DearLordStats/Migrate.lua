-- DearLord Stats : one-time data repairs
-- Reserved for small, versioned fix-ups of saved data after a breaking change.
-- Nothing is pending. The file stays in the load list so that adding a repair later does not
-- require a full client restart (new files in a .toc are only picked up when the game starts).
local ADDON, ns = ...
