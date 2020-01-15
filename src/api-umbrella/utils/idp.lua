local cjson = require "cjson"
local config = require "api-umbrella.proxy.models.file_config"
local jwt = require "resty.jwt"
local http = require "resty.http"
local _M = {}

local function get_idm_user_info(token, dict)
    local idp_host, result, res, err, rpath, resource, method
    local app_id = dict["app_id"]
    local mode = dict["mode"]
    local idp_back_name = dict["idp"]["backend_name"]
    local headers = {}
    local ssl = false
    local httpc = http.new()
    httpc:set_timeout(45000)

    if config["nginx"]["lua_ssl_trusted_certificate"] then
        ssl=true
    end

    local rquery =  "access_token="..token
    if idp_back_name == "google-oauth2" then
        rpath = "/oauth2/v3/userinfo"
        idp_host="https://www.googleapis.com"
    elseif idp_back_name == "fiware-oauth2" and mode == "authorization" then
        rpath = "/user"
        idp_host = dict["idp"]["host"]
        resource = ngx.ctx.uri
        method = ngx.ctx.request_method
        rquery = "access_token="..token.."&app_id="..app_id.."&resource="..resource.."&action="..method
    elseif idp_back_name == "fiware-oauth2" and mode == "authentication" then
        rpath = "/user"
        idp_host = dict["idp"]["host"]
        rquery = "access_token="..token.."&app_id="..app_id
    elseif idp_back_name == "keycloak-oauth2" then
        rpath = "/auth/realms/"..dict["idp"]["realm"].."/protocol/openid-connect/userinfo"
        idp_host = dict["idp"]["host"]
        rquery = ""
        headers["Authorization"] = "Bearer "..token
    elseif idp_back_name == "facebook-oauth2" then
        rpath = "/me"
        idp_host="https://graph.facebook.com"
        rquery = "fields=id,name,email&access_token="..token
    elseif idp_back_name == "github-oauth2" then
        rpath = "/user"
        idp_host="https://api.github.com"
    end

    res, err =  httpc:request_uri(idp_host..rpath, {
        method = "GET",
        query = rquery,
        headers = headers,
        ssl_verify = ssl,
    })

    if res and (res.status == 200 or res.status == 201) then
        local body = res.body
        if not body then
            return nil
        end
        result = cjson.decode(body)

        if idp_back_name == "fiware-oauth2" then
            -- Process organization info to generate organization scope roles
            if result["organizations"] ~= nil then
                for _, org in ipairs(result["organizations"]) do
                    for _, org_role in ipairs(org["roles"]) do
                        -- Generate organization role
                        local role_name = org["id"] .. "."
                        role_name = role_name .. org_role["name"]

                        ngx.log(ngx.INFO, "Generated org role: ", role_name)
                        result["roles"][#result["roles"] + 1] = role_name
                    end
                end
            end
        end
    end

    return result, err
end

local function get_jwt_user_info(token, dict)
    local result, err
    local idp_back_name = dict["idp"]["backend_name"]

    if idp_back_name == "keycloak-oauth2" then
        -- Parse the JWT token
        local decoded_token = jwt:verify(dict["idp"]["key"], token)

        if not decoded_token["valid"] then
            return nil, "The provided JWT is not valid"
        end

        local parsed_token = decoded_token["payload"]
        result = {}

        result["email"] = parsed_token["email"]
        result["roles"] = {}

        -- Load roles info
        if parsed_token["realm_access"] ~= nil then
            for _, role in ipairs(parsed_token["realm_access"]["roles"]) do
                ngx.log(ngx.INFO, "Generated realm role: ", role_name)

                result["roles"][#result["roles"] + 1] = "realm."..role
            end
        end

        if parsed_token["resource_access"][dict["app_id"]] ~= nil then
            for _, role in ipairs(parsed_token["resource_access"][dict["app_id"]]["roles"]) do
                result["roles"][#result["roles"] + 1] = role
            end
        end
    end

    return result, err
end

-- Function to connect with an IdP service (Google, Facebook, Fiware, Github) for checking
-- if a token is valid and retrieve the user properties. The function takes
-- the token provided by the user and the IdP provider registered in the api-backend
-- for checking if the token is valid making a validation request to the corresponding IdP.
-- If the token is valid, the user information stored in the IdP is retrieved.

function _M.first(dict)
    local token = dict["key_value"]
    local result, err

    if not dict["idp"]["jwt_enabled"] then
        result, err = get_idm_user_info(token, dict)
    else
        result, err = get_jwt_user_info(token, dict)
    end

    return result, err
end

return _M