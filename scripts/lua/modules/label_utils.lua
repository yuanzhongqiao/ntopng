--
-- (C) 2014-24 - ntop.org
--

-- This file contains a small set of utility functions for managing labels, e.g. aliases

require "ntop_utils"

-- ##############################################

local function label2formattedlabel(alt_name, host_info, show_vlan, shorten_len)
    if not isEmptyString(alt_name) then
        local ip = host_info["ip"] or host_info["host"]
        -- Make it shorter
        local res = alt_name

        -- Special shorting function for IP addresses
        if res ~= ip then
            if (not shorten_len) or (shorten_len == false) then
                -- Don't touch the string, requested as-is without shortening
            elseif tonumber(shorten_len) then
                -- Shorten according to the specified length
                res = shortenString(res, shorten_len)
            else
                -- Use the default system-wide setting for the shortening
                res = shortenString(res)
            end
        end

        -- Adding the vlan if requested
        if show_vlan then
            local vlan = tonumber(host_info["vlan"])

            if vlan and vlan > 0 then
                local full_vlan_name = getFullVlanName(vlan, true --[[ Compact --]] )

                res = string.format("%s@%s", res, full_vlan_name)
            end
        end

        return res
    end

    -- Fallback: just the IP and VLAN
    return (hostinfo2hostkey(host_info, true))
end

-- ##############################################

-- Attempt at retrieving an host label from an host_info, using local caches and DNS resolution.
-- This can be more expensive if compared to only using information found inside host_info.
local function hostinfo2label_resolved(host_info, show_vlan, shorten_len, skip_resolution)
    local ip = host_info["ip"] or host_info["host"]
    local res

    -- If local broadcast domain host and DHCP, try to get the label associated
    -- to the MAC address
    if host_info["mac"] and (host_info["broadcast_domain_host"] or host_info["dhcpHost"]) then
        res = getHostAltName(host_info["mac"])
    end

    -- In case no resolution is requested, directly skip this part
    if (isEmptyString(res)) and (not skip_resolution) then
        -- Try and get the resolved name
        res = ntop.getResolvedName(ip)

        if not isEmptyString(res) then
            res = string.lower(res)
        else
            -- Nothing found, just fallback to the IP address
            res = ip
        end
    end

    return label2formattedlabel(res, host_info, show_vlan, shorten_len)
end

-- ##############################################
-- Just a convenience function for hostinfo2label with only IP and VLAN
function ip2label(ip, vlan, shorten_len)
    return hostinfo2label({
        host = ip,
        vlan = (vlan or 0)
    }, true, shorten_len)
end

-- ##############################################

-- URL Util --

--
-- Split the host key (ip@vlan) creating a new lua table.
-- Example:
--    info = hostkey2hostinfo(key)
--    ip = info["host"]
--    vlan = info["vlan"]
--
function hostkey2hostinfo(key)
  local host = {}
  local info = split(key,"@")

  if(info[1] ~= nil) then
    host["host"] = info[1]
  end

  if(info[2] ~= nil) then
    host["vlan"] = tonumber(info[2])
  else
    host["vlan"] = 0
  end

  return host
end

-- ##############################################

-- Retrieve an host label from an host_info. The minimum fields of
-- the host_info are "host" and "vlan", however a full JSON from Host::lua
-- is needed to provide an accurate result.
--
-- The following order is used to determine the label:
--    MAC label (LBD hosts only), IP label, MDNS/DHCP name from C, resolved IP
--
-- NOTE: The function attempt at labelling an host only using information found in host_info.
-- In case host_info is not enough to label the host, then local caches and DNS resolution kick in
-- to find a label (at the expense of extra time).
function hostinfo2label(host_info, show_vlan, shorten_len, skip_resolution)
    require "lua_utils"
    local alt_name = nil
    local ip = host_info["ip"] or host_info["host"]

    -- Take the label as found in the host structure
    local res = host_info.label

    if isEmptyString(res) then
        -- Use any user-configured custom name
        -- This goes first as a label set by the user MUST take precedance over any other possibly available label
        res = getHostAltName(ip)

        if isEmptyString(res) then
            -- Read what is found inside host `name`, e.g., name as found by dissected traffic such as DHCP
            res = host_info["name"]

            if isEmptyString(res) then
                return hostinfo2label_resolved(host_info, show_vlan, shorten_len, skip_resolution)
            end
        end
    end

    return label2formattedlabel(res, host_info, show_vlan, shorten_len)
end

-- ##############################################

--
-- Analyze the host_info table and return the host key.
-- Example:
--    host_info = interface.getHostInfo("127.0.0.1",0)
--    key = hostinfo2hostkey(host_info)
--
function hostinfo2hostkey(host_info, host_type, show_vlan)
   local rsp = ""

   if(host_type == "cli") then
      local cli_ip = host_info["cli.ip"] or host_info["cli_ip"]

      if cli_ip then
	 rsp = rsp..cli_ip
      end

   elseif(host_type == "srv") then
      local srv_ip = host_info["srv.ip"] or host_info["srv_ip"]

      if srv_ip then
	 rsp = rsp..srv_ip
      end
   else

      if(host_info["ip"] ~= nil) then
	 rsp = rsp..host_info["ip"]
      elseif(host_info["mac"] ~= nil) then
	 rsp = rsp..host_info["mac"]
      elseif(host_info["host"] ~= nil) then
	 rsp = rsp..host_info["host"]
      elseif(host_info["name"] ~= nil) then
	 rsp = rsp..host_info["name"]
      end
   end

   local vlan_id = tonumber(host_info["vlan"] or host_info["vlan_id"] or 0)

   if vlan_id ~= 0 or show_vlan then
      rsp = rsp..'@'..tostring(vlan_id)
   end

   return rsp
end

-- ##############################################

function getHostAltNamesKey(host_key)
    if (host_key == nil) then
        return (nil)
    end
    return "ntopng.cache.host_labels." .. host_key
end

-- ##############################################

function getHostAltName(host_info)
    local host_key

    -- Check if there is an alias for the host@vlan
    -- Note: this is not used for backward compatibility (see setHostAltName)
    -- if type(host_info) == "table" and host_info["vlan"] then
    --    host_key = hostinfo2hostkey(host_info)
    --    alt_name = ntop.getCache(getHostAltNamesKey(host_key))
    --    return alt_name
    -- end

    -- Check if there is an alias for the host
    if type(host_info) == "table" then
        host_key = host_info["host"]
    else
        host_key = host_info
    end

    return ntop.getCache(getHostAltNamesKey(host_key))
end

-- ##############################################

function setHostAltName(host_info, alt_name)
    local host_key

    if type(host_info) == "table" then
        -- Note: we are not using hostinfo2hostkey which includes the
        -- vlan for backward compatibility, compatibility with
        -- the backend, and compatibility with the vpn scripts
        host_key = host_info["host"] -- hostinfo2hostkey(host_info)
    else
        host_key = host_info
    end

    local key = getHostAltNamesKey(host_key)

    if isEmptyString(alt_name) then
        ntop.delCache(key)
    else
        ntop.setCache(key, alt_name)
    end
end

-- ##############################################

function getLocalNetworkAliasKey()
    return "ntopng.network_aliases"
end

-- ##############################################

function getInterfaceAliasKey(ifid)
    return "ntopng.prefs.ifid_" .. ifid .. ".name"
end

-- ##############################################

function getLocalNetworkAliasById(network)
    local network_utils = require "network_utils"

    local networks_stats = interface.getNetworksStats()
    local network_id = tonumber(network)

    -- If network is (u_int8_t)-1 then return an empty value
    if network == nil or network == network_utils.UNKNOWN_NETWORK then
        return ' '
    end

    local label = ''
    for n, ns in pairs(networks_stats) do
        if ns.network_id == network_id then
            label = getFullLocalNetworkName(ns.network_key)
        end
    end
    return label
end

-- ##############################################

function getLocalNetworkAlias(network)
    local alias = ntop.getLocalNetworkAlias(network) or nil

    if not alias then
        alias = ntop.getHashCache(getLocalNetworkAliasKey(), network)
    end

    if not isEmptyString(alias) then
        return alias
    end

    return network
end

-- ##############################################

function getLocalNetworkLabel(network)
    local alias = getLocalNetworkAlias(network)

    if alias ~= network then
        return string.format("%s  · %s", alias, network)
    end

    return network
end

-- ##############################################

function getFullLocalNetworkName(network)
    local alias = getLocalNetworkAlias(network)

    if tonumber(network) == 65535 then
        return ""
    end

    if alias ~= network then
        return string.format("%s [%s]", alias, network)
    end

    return network
end

-- ##############################################

function getVlanAliasKey()
    return "ntopng.vlan_aliases"
end

-- ##############################################

function getVlanAlias(vlan_id)
    local alias = ntop.getHashCache(getVlanAliasKey(), vlan_id)

    if not isEmptyString(alias) then
        return alias
    end

    return tostring(vlan_id)
end

-- ##############################################

function getFullVlanName(vlan_id, compact, return_untagged)
    local alias = getVlanAlias(vlan_id)

    -- In case of vlan 0, return empty string as name
    -- fix for untagged vlan (#7998)
    if tonumber(vlan_id) == 0 then
        if (return_untagged) then
            return i18n('no_vlan')
        end
        return ''
    end

    if not isEmptyString(alias) then
        if not isEmptyString(alias) and alias ~= tostring(vlan_id) then
            if compact then
                alias = shortenString(alias)
                return string.format("%s", alias)
            else
                return string.format("%u [%s]", vlan_id, alias)
            end
        end
    end

    return vlan_id
end
