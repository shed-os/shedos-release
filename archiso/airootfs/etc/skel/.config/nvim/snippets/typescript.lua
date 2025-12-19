-- Custom TypeScript Snippets
-- Backend API focused

local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local fmt = require("luasnip.extras.fmt").fmt

return {
  -- Express Route Handler
  s("route", fmt([[
router.{}('{}', async (req: Request, res: Response) => {{
  try {{
    {}
    res.status({}).json({});
  }} catch (error) {{
    console.error(error);
    res.status(500).json({{ error: 'Internal server error' }});
  }}
}});
]], {
    i(1, "get"),
    i(2, "/path"),
    i(3, "// TODO: implement"),
    i(4, "200"),
    i(5, "data"),
  })),

  -- Async Function
  s("afn", fmt([[
async function {}({}): Promise<{}> {{
  {}
}}
]], {
    i(1, "functionName"),
    i(2, "params"),
    i(3, "ReturnType"),
    i(4, "// TODO: implement"),
  })),

  -- Interface
  s("int", fmt([[
interface {} {{
  {}: {};
  {}
}}
]], {
    i(1, "InterfaceName"),
    i(2, "field"),
    i(3, "string"),
    i(4),
  })),

  -- API Response Type
  s("apiresponse", fmt([[
interface {}Response {{
  success: boolean;
  data?: {};
  error?: string;
  message?: string;
}}
]], {
    i(1, "Resource"),
    i(2, "any"),
  })),
}
