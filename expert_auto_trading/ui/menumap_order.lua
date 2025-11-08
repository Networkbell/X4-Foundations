local function findMenuByName(name)
  if Menus then
    for _, m in ipairs(Menus) do
      if m.name == name then return m end
    end
  end
end

local function dedup(list)
  local seen, out = {}, {}
  for _, id in ipairs(list) do
    if not seen[id] then
      seen[id] = true
      table.insert(out, id)
    end
  end
  return out
end

local function init()
  local mapMenu = findMenuByName("MapMenu")
  if not mapMenu then return end

  mapMenu.uix_callbacks = mapMenu.uix_callbacks or {}
  mapMenu.uix_callbacks["onShowMenu_orderdefs_forcedorderatfront"] = mapMenu.uix_callbacks["onShowMenu_orderdefs_forcedorderatfront"] or {}

  mapMenu.uix_callbacks["onShowMenu_orderdefs_forcedorderatfront"]["EnhancedAutoTradeAutoMine"] = function(current)
    return dedup({
      "TradeRoutine_Basic",
      "TradeRoutine_BasicMid",
      "TradeRoutine_Standard",
      "TradeRoutine_Advanced",
      "TradeRoutine_Expert"
    })
  end
end

init()