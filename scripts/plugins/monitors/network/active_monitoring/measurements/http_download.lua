--
-- (C) 2020 - ntop.org
--

local ts_utils = require("ts_utils_core")

local do_trace = false

-- #################################################################

-- This is the script state, which must be manually cleared in the check
-- function. Can be then used in the collect_results function to match the
-- probe requests with probe replies.
local result = {}

-- #################################################################

-- The function called periodically to send the host probes.
-- hosts contains the list of hosts to probe, The table keys are
-- the hosts identifiers, whereas the table values contain host information
-- see (am_utils.key2host for the details on such format).
local function check(measurement, hosts, granularity)
  result[measurement] = {}

  for key, host in pairs(hosts) do
    local domain_name = host.host

    if do_trace then
      print("[ActiveMonitoring] GET "..domain_name.."\n")
    end

    -- HTTP results are retrieved immediately
    local rv
    if host.token then
      --[[
      local suffix = string:sub(-domain_name.len("/"))
      if (suffix == "/") then
        domain_name = domain_name .. "lua/10mb.lua"
      else
        domain_name = domain_name .. "/lua/10mb.lua"
      end
      ]]

      rv = ntop.httpGetAuthToken(domain_name, host.token, 10 --[[ timeout ]], host.save_result == false --[[ whether to return the content --]],
				  nil, true --[[ follow redirects ]])
    else
       rv = ntop.httpGet(domain_name, nil, nil, 10 --[[ timeout ]], host.save_result == false --[[ whether to return the content --]],
			 nil, true --[[ don't follow redirects ]])
    end

    if(rv and rv.HTTP_STATS and (rv.HTTP_STATS.TOTAL_TIME > 0)) then
      local download_bit = rv.BYTES_DOWNLOAD * 8
      local total_time = rv.HTTP_STATS.TOTAL_TIME
      local lookup_time = (rv.HTTP_STATS.NAMELOOKUP_TIME or 0)

      local bandwidth = (download_bit / total_time) / 1000000

      result[measurement][key] = {
	    value = bandwidth,
        resolved_addr = rv.RESOLVED_IP,
	 }
    end
  end
end

-- #################################################################

-- @brief HTTPS check
local function check_http_download(hosts, granularity)
   check("http", hosts, granularity)
end

-- #################################################################

-- The function responsible for collecting the results.
-- It must return a table containing a list of hosts along with their retrieved
-- measurement. The keys of the table are the host key. The values have the following format:
--  table
--	resolved_addr: (optional) the resolved IP address of the host
--	value: (optional) the measurement numeric value. If unspecified, the host is still considered unreachable.
local function collect(measurement, granularity)
  -- TODO: curl_multi_perform could be used to perform the requests
  -- asynchronously, see https://curl.haxx.se/libcurl/c/curl_multi_perform.html
  return result[measurement]
end

-- #################################################################

local function collect_http_download(granularity)
   -- TODO: curl_multi_perform could be used to perform the requests
   -- asynchronously, see https://curl.haxx.se/libcurl/c/curl_multi_perform.html
   return collect("http", granularity)
end

-- #################################################################

return {
    -- Defines a list of measurements implemented by this script.
    -- The probing logic is implemented into the check() and collect_results().
    --
    -- Here is how the probing occurs:
    --	1. The check function is called with the list of hosts to probe. Ideally this
    --	   call should not block (e.g. should not wait for the results)
    --	2. The active_monitoring.lua code sleeps for some seconds
    --	3. The collect_results function is called. This should retrieve the results
    --       for the hosts checked in the check() function and return the results.
    --
    -- The alerts for non-responding hosts and the Active Monitoring timeseries are automatically
    -- generated by active_monitoring.lua . The timeseries are saved in the following schemas:
    -- "am_host:val_min", "am_host:val_5mins", "am_host:val_hour".
    measurements = {
       {
      -- The unique key for the measurement
      key = "throughput",
      -- The localization string for this measurement
      i18n_label = "active_monitoring_stats.http_download",
      -- The function called periodically to send the host probes
      check = check_http_download,
      -- The function responsible for collecting the results
      collect_results = collect_http_download,
      -- The granularities allowed for the probe. See supported_granularities in active_monitoring.lua
      granularities = {"min", "5mins", "hour"},
      -- The localization string for the measurement unit (e.g. "ms", "Mbits")
      i18n_unit = "field_units.mbits",
      -- The localization string for the Jitter unit (e.g. "ms", "Mbits")
      i18n_jitter_unit = nil,
      -- The localization string for the Active Monitoring timeseries menu entry
      i18n_am_ts_label = "active_monitoring_stats.throughput",
      -- The localization string for the Active Monitoring metric in the chart
      i18n_am_ts_metric = "active_monitoring_stats.throughput",
      -- The operator to use when comparing the measurement with the threshold, "gt" for ">" or "lt" for "<".
      operator = "lt",
      -- If set, indicates a maximum threshold value
      max_threshold = 10000,
      -- If set, indicates the default threshold value
      default_threshold = nil,
      -- A list of additional timeseries (the am_host:val_* is always shown) to show in the charts.
      -- See https://www.ntop.org/guides/ntopng/api/timeseries/adding_new_timeseries.html#charting-new-metrics .
      additional_timeseries = nil,
      -- Js function to call to format the measurement value. See ntopng_utils.js .
      value_js_formatter = "NtopUtils.fbits",
      -- The raw measurement value is multiplied by this factor before being written into the chart
      chart_scaling_value = 1000000,
      -- A list of additional notes (localization strings) to show into the timeseries charts
      i18n_chart_notes = {},
      -- If set, the user cannot change the host
      force_host = nil,
      -- An alternative localization string for the unrachable alert message
      unreachable_alert_i18n = "alert_messages.http_download_failed",
       },
    },
 
    -- A setup function to possibly disable the plugin
    setup = nil,
 }
