-- Official Atlas sprite sheets, bundled for offline planning.
local M={}
function M.load(version)
	version=version:gsub("%-ruthless$","")
	local file=assert(io.open("Assets/Atlas/"..version.."/manifest.json","r"))
	local data=assert(require("dkjson").decode(file:read("*a")));file:close()
	local handles={}
	local art={sprites=data.sprites}
	function art:draw(category,key,x,y,scale)
		local sheet=self.sprites[category]
		local rect=sheet and sheet.coords[key]
		if not rect then return end
		local handle=handles[sheet.filename]
		if not handle then handle=NewImageHandle();handle:Load(sheet.filename);handles[sheet.filename]=handle end
		local w,h=rect.w*scale,rect.h*scale
		DrawImage(handle,x-w/2,y-h/2,w,h,rect.x/sheet.w,rect.y/sheet.h,(rect.x+rect.w)/sheet.w,(rect.y+rect.h)/sheet.h)
	end
	return art
end
return M
