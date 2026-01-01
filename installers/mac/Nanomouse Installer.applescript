-- Nanomouse 拼音输入法安装器
-- 双击运行即可安装

on run
	-- 检查鼠须管是否安装（使用 shell 命令检测）
	try
		do shell script "test -d '/Library/Input Methods/Squirrel.app'"
		set squirrelInstalled to true
	on error
		set squirrelInstalled to false
	end try
	
	if not squirrelInstalled then
		-- 检查是否有 Homebrew
		try
			do shell script "which brew"
			set hasHomebrew to true
		on error
			set hasHomebrew to false
		end try
		
		if hasHomebrew then
			-- 有 Homebrew，询问是否自动安装
			display dialog "❌ 未检测到鼠须管输入法！

检测到您已安装 Homebrew，是否自动安装鼠须管？" buttons {"手动下载", "自动安装"} default button "自动安装" with icon caution
			
			if button returned of result is "自动安装" then
				display dialog "⏳ 正在安装鼠须管，请稍候...

这可能需要几分钟时间。" buttons {} giving up after 1
				try
					do shell script "/opt/homebrew/bin/brew install --cask squirrel 2>&1 || /usr/local/bin/brew install --cask squirrel 2>&1"
					display dialog "✅ 鼠须管安装成功！

请注意：安装后可能需要：
1. 注销并重新登录
2. 在系统设置中添加鼠须管输入法

完成后请重新运行此安装器。" buttons {"好的"} default button "好的" with icon note
					return
				on error errMsg
					display dialog "❌ 自动安装失败：" & errMsg & "

请手动下载安装。" buttons {"打开下载页面"} default button "打开下载页面" with icon stop
					open location "https://rime.im/download/"
					return
				end try
			else
				open location "https://rime.im/download/"
				return
			end if
		else
			-- 没有 Homebrew，引导手动下载
			display dialog "❌ 未检测到鼠须管输入法！

请先从 https://rime.im/download/ 下载安装鼠须管，然后重新运行此安装器。" buttons {"打开下载页面", "取消"} default button "打开下载页面" with icon stop
			if button returned of result is "打开下载页面" then
				open location "https://rime.im/download/"
			end if
			return
		end if
	end if
	
	-- 确认安装
	display dialog "🐭 Nanomouse 拼音输入法

功能：
• 用 nn 代替 ng 输入后鼻音
• 用 vn 代替 uan 输入
• 用 vnn 代替 uang 输入
• 默认使用简体中文

点击「安装」开始安装配置。" buttons {"取消", "安装"} default button "安装" with icon note
	
	if button returned of result is "取消" then
		return
	end if
	
	-- 执行安装
	try
		set myPath to POSIX path of (path to me)
		set scriptPath to myPath & "Contents/MacOS/install_core.sh"
		
		do shell script "bash " & quoted form of scriptPath
		
		display dialog "✅ 安装成功！

测试方法：
• 输入 dann → 当、档、党
• 输入 gvn → 关、官、管
• 输入 gvnn → 光、广、逛

如果没有生效，请点击菜单栏鼠须管图标 → 部署" buttons {"完成"} default button "完成" with icon note
		
	on error errMsg
		display dialog "❌ 安装失败：" & errMsg buttons {"确定"} default button "确定" with icon stop
	end try
end run
