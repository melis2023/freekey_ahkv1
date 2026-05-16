; ============================================================
;  freekeyAutomation.ahk  —  游戏取色识别按键循环工具
;  版本: v1.0
;  语言: AutoHotkey v1 (AHK v1.1+)
;  核心: 屏幕取色识别 → 条件触发自动按键
;  说明: 单文件，不依赖外部库，纯内置函数实现
; ============================================================

#NoEnv
#SingleInstance Force
#Persistent

#InstallKeybdHook
#UseHook
#MaxMem 256
#KeyHistory 0
SendMode Input
CoordMode, Pixel, Screen
CoordMode, Mouse, Screen
SetBatchLines, -1
ListLines Off

; ============================================================
;  全局变量
; ============================================================
; --- 文件路径 ---
global CONFIG_DIR := A_ScriptDir
global CONFIG_PATH := CONFIG_DIR . "\config.ini"

; --- 运行状态 ---
global isRunning := 0           ; 0=停止, 1=运行中
global loopInterval := 50       ; 主循环间隔(ms)

; --- 热键配置 ---
global startHotkey := "Capslock"
global panelHotkey := "F10"

global lastFireTime := 0
global lastFireName := ""

; --- 触发器列表 ---
global triggers := Object()     ; 关联数组, key=触发器名称
global triggerNames := []       ; 名称列表(保持顺序)
global triggerCount := 0

; --- 顺序执行状态 ---
global currentTriggerIdx := 1   ; 当前检查的触发器索引(1-based)
global waitUntilTick := 0       ; 等待到此时间戳后才执行下一个

; --- 缓存 HWND ---
global g_btnSaveHwnd := 0

; --- 取色状态 ---
global isPicking := 0
global pickTargetGui := ""      ; 返回哪个GUI
global pickTargetX := ""        ; X控件名
global pickTargetY := ""        ; Y控件名
global pickTargetColor := ""    ; Color控件名
global pickReturnLabel := ""    ; 取色完成后跳转的标签

; ============================================================
;  自动执行段 — 初始化
; ============================================================
gosub, InitApp

; 脚本常驻
return

; ============================================================
;  初始化流程
; ============================================================
InitApp:
    ; 创建配置目录
    FileCreateDir, %CONFIG_DIR%

    ; 初始化配置
    gosub, InitConfig

    ; 读取配置
    gosub, ReadConfig

    ; 注册热键
    gosub, RegisterHotkeys

    ; 启动主循环定时器(初始为停止状态)
    SetTimer, MainLoop, %loopInterval%

    ; 注册退出自动保存
    OnExit, ExitSub

    ; 显示启动完成提示
    gosub, UpdateStatusDisplay
return

; ============================================================
;  T2: INI 配置层
; ============================================================
InitConfig:
    if !FileExist(CONFIG_PATH)
    {
        ; 写入默认配置
        IniWrite, %startHotkey%, %CONFIG_PATH%, 热键设置, 启动热键
        IniWrite, %panelHotkey%, %CONFIG_PATH%, 热键设置, 面板热键
        IniWrite, %loopInterval%, %CONFIG_PATH%, 循环设置, 检测间隔(ms)
    }
return

ReadConfig:
    ; 读取热键设置
    IniRead, startHotkey, %CONFIG_PATH%, 热键设置, 启动热键, Capslock
    IniRead, panelHotkey, %CONFIG_PATH%, 热键设置, 面板热键, F10

    ; 读取循环设置
    IniRead, loopInterval, %CONFIG_PATH%, 循环设置, 检测间隔(ms), 50
    if (loopInterval < 10)
        loopInterval := 10
    if (loopInterval > 1000)
        loopInterval := 1000

    ; 读取触发器列表（逗号分隔）
    triggers := Object()
    triggerNames := []
    triggerCount := 0

    IniRead, rawNames, %CONFIG_PATH%, 触发器列表, 名称, %A_Space%
    rawNames := Trim(rawNames)
    if (rawNames != "" && rawNames != "ERROR")
    {
        nameArr := StrSplit(rawNames, ",")
        for idx, trigName in nameArr
        {
            trigName := Trim(trigName)
            if (trigName = "")
                continue

            trigObj := ReadOneTrigger(trigName)
            if (trigObj.name != "")
            {
                triggers[trigName] := trigObj
                triggerNames.Push(trigName)
            }
        }
    }
    triggerCount := triggerNames.Length()
return

ReadOneTrigger(name) {
    obj := Object()
    obj.name := ""

    IniRead, _tmp_name, %CONFIG_PATH%, %name%, 名称, %A_Space%
    if (_tmp_name = "" || _tmp_name = "ERROR")
        return obj

    obj.name := _tmp_name

    ; AHK v1命令不能直接用obj.prop作为输出变量，必须用临时变量中转
    IniRead, _tmp_val, %CONFIG_PATH%, %name%, 按键, 1
    obj.key := _tmp_val
    IniRead, _tmp_val, %CONFIG_PATH%, %name%, 坐标X, 0
    obj.x := _tmp_val
    IniRead, _tmp_val, %CONFIG_PATH%, %name%, 坐标Y, 0
    obj.y := _tmp_val
    IniRead, _tmp_val, %CONFIG_PATH%, %name%, 颜色, 0xFFFFFF
    obj.color := _tmp_val
    IniRead, _tmp_val, %CONFIG_PATH%, %name%, 色差, 0
    obj.variation := _tmp_val
    IniRead, _tmp_val, %CONFIG_PATH%, %name%, 延迟(ms), 500
    obj.minInterval := _tmp_val
    IniRead, _tmp_val, %CONFIG_PATH%, %name%, 启用, 1
    obj.enabled := _tmp_val
    obj.lastTriggered := 0

    return obj
}

WriteConfig:
    ; 写入热键设置
    IniWrite, %startHotkey%, %CONFIG_PATH%, 热键设置, 启动热键
    IniWrite, %panelHotkey%, %CONFIG_PATH%, 热键设置, 面板热键

    ; 写入循环设置
    IniWrite, %loopInterval%, %CONFIG_PATH%, 循环设置, 检测间隔(ms)

    ; 清除旧的触发器列表节，用新格式重写
    IniDelete, %CONFIG_PATH%, 触发器列表

    ; 构建逗号分隔的名称列表
    nameList := ""
    for idx, tName in triggerNames
    {
        obj := triggers[tName]
        section := tName

        ; 拼接名称到逗号分隔字符串
        if (nameList != "")
            nameList .= ","
        nameList .= tName

        _tv := obj.name
        IniWrite, %_tv%, %CONFIG_PATH%, %section%, 名称
        _tv := obj.key
        IniWrite, %_tv%, %CONFIG_PATH%, %section%, 按键
        _tv := obj.x
        IniWrite, %_tv%, %CONFIG_PATH%, %section%, 坐标X
        _tv := obj.y
        IniWrite, %_tv%, %CONFIG_PATH%, %section%, 坐标Y
        _tv := obj.color
        IniWrite, %_tv%, %CONFIG_PATH%, %section%, 颜色
        _tv := obj.variation
        IniWrite, %_tv%, %CONFIG_PATH%, %section%, 色差
        _tv := obj.minInterval
        IniWrite, %_tv%, %CONFIG_PATH%, %section%, 延迟(ms)
        _tv := obj.enabled
        IniWrite, %_tv%, %CONFIG_PATH%, %section%, 启用
    }

    ; 写入逗号分隔的触发器名称列表
    IniWrite, %nameList%, %CONFIG_PATH%, 触发器列表, 名称
return

; ============================================================
;  T3: 颜色检测函数
; ============================================================
; 获取指定坐标的颜色值(RGB格式, 返回6位十六进制, 如 FF00FF)
GetPixelColor(x, y)
{
    PixelGetColor, rawColor, %x%, %y%, RGB
    ; RGB格式返回 0xRRGGBB, 去掉前缀保留6位
    StringRight, hexColor, rawColor, 8
    ; 如果带0x前缀也去掉
    StringReplace, hexColor, hexColor, 0x, %A_Space%
    StringReplace, hexColor, hexColor, #, %A_Space%
    hexColor := Trim(hexColor)
    ; 补全到6位
    while (StrLen(hexColor) < 6)
        hexColor := "0" . hexColor
    return hexColor
}

; 检查指定坐标的颜色是否匹配(含色差容差)
ColorMatches(x, y, targetColor, variation := 0)
{
    screenColor := GetPixelColor(x, y)

    if (variation = 0)
    {
        ; 精确匹配
        return (screenColor = targetColor) ? 1 : 0
    }
    else
    {
        ; 带色差匹配 — 逐分量比较
        targetR := HexStrToInt(SubStr(targetColor, 1, 2))
        targetG := HexStrToInt(SubStr(targetColor, 3, 2))
        targetB := HexStrToInt(SubStr(targetColor, 5, 2))

        screenR := HexStrToInt(SubStr(screenColor, 1, 2))
        screenG := HexStrToInt(SubStr(screenColor, 3, 2))
        screenB := HexStrToInt(SubStr(screenColor, 5, 2))

        diffR := Abs(targetR - screenR)
        diffG := Abs(targetG - screenG)
        diffB := Abs(targetB - screenB)

        if (diffR <= variation && diffG <= variation && diffB <= variation)
            return 1
        else
            return 0
    }
}

; 判断触发器的颜色条件是否满足
IsTriggerConditionMet(trigger)
{
    return ColorMatches(trigger.x, trigger.y, trigger.color, trigger.variation)
}

; 辅助: 单个十六进制字符转为数值(0-15)
HexCharToInt(ch)
{
    if (ch >= "0" && ch <= "9")
        return Asc(ch) - 48  ; Asc("0")=48
    if (ch >= "A" && ch <= "F")
        return Asc(ch) - 55  ; Asc("A")=65 → 10
    if (ch >= "a" && ch <= "f")
        return Asc(ch) - 87  ; Asc("a")=97 → 10
    return 0
}

; 辅助: 十六进制字符串转整数
HexStrToInt(hexStr)
{
    result := 0
    loop, % StrLen(hexStr)
    {
        ch := SubStr(hexStr, A_Index, 1)
        result := result * 16 + HexCharToInt(ch)
    }
    return result
}

; 格式化颜色值: 统一转为6位十六进制(无前缀)
FormatColor(rawColor)
{
    ; 去掉 0x 和 # 前缀
    StringReplace, rawColor, rawColor, 0x, %A_Space%
    StringReplace, rawColor, rawColor, #, %A_Space%
    rawColor := Trim(rawColor)
    ; 补全到6位
    while (StrLen(rawColor) < 6)
        rawColor := "0" . rawColor
    StringUpper, rawColor, rawColor
    return rawColor
}

; ============================================================
;  T4: 按键执行函数
; ============================================================
; 发送按键 — 自动处理修饰符和特殊键
PressKey(key)
{
    if (key = "")
        return

    ; 检测是否为修饰符组合键
    modifier := ""
    actualKey := key

    if (SubStr(key, 1, 1) = "^")      ; Ctrl
        modifier := "^", actualKey := SubStr(key, 2)
    else if (SubStr(key, 1, 1) = "!")  ; Alt
        modifier := "!", actualKey := SubStr(key, 2)
    else if (SubStr(key, 1, 1) = "+")  ; Shift
        modifier := "+", actualKey := SubStr(key, 2)
    else if (SubStr(key, 1, 1) = "#")  ; Win
        modifier := "#", actualKey := SubStr(key, 2)

    ; 判断是否为特殊功能键(需要用 {} 包裹)
    if IsSpecialKey(actualKey)
        actualKey := "{" . actualKey . "}"

    fullKey := modifier . actualKey
    SendInput, %fullKey%
}

; 判断是否为需要 {} 包裹的特殊键
IsSpecialKey(key)
{
    static specialList := "F1,F2,F3,F4,F5,F6,F7,F8,F9,F10,F11,F12"
        . ",LButton,RButton,MButton"
        . ",LControl,RControl,LAlt,RAlt"
        . ",LShift,RShift,LWin,RWin"
        . ",Space,Tab,Enter,Escape,Esc,Backspace,BS,Delete,Del"
        . ",Insert,Ins,Home,End,PgUp,PgDn,PageUp,PageDown"
        . ",Up,Down,Left,Right"
        . ",ScrollLock,CapsLock,NumLock"
        . ",Numpad0,Numpad1,Numpad2,Numpad3,Numpad4,Numpad5,Numpad6,Numpad7,Numpad8,Numpad9"
        . ",NumpadDot,NumpadEnter,NumpadAdd,NumpadSub,NumpadMult,NumpadDiv"
        . ",PrintScreen,Pause,Break,AppsKey,Sleep"

    if InStr("," . specialList . ",", "," . key . ",")
        return 1
    return 0
}

; ============================================================
;  T5: 主循环系统
; ============================================================
MainLoop:
    if !isRunning
        return

    currentTick := A_TickCount

    ; 等待延迟中，跳过本轮
    if (currentTick < waitUntilTick)
    {
        gosub, UpdateStatusDisplay
        return
    }

    ; 无触发器
    if (triggerNames.Length() = 0)
        return

    ; 修正索引
    if (currentTriggerIdx > triggerNames.Length())
        currentTriggerIdx := 1

    ; 检查当前触发器
    tName := triggerNames[currentTriggerIdx]
    trig := triggers[tName]

    if trig.enabled && (currentTick - trig.lastTriggered >= trig.minInterval)
    {
        if IsTriggerConditionMet(trig)
        {
            ; 条件满足 → 执行按键
            PressKey(trig.key)
            trig.lastTriggered := currentTick
            lastFireTime := currentTick
            lastFireName := trig.name

            ; 设置延迟: 等待该触发器的"最小间隔"后检查下一个
            waitUntilTick := currentTick + trig.minInterval
        }
    }

    ; 无论是否触发，都前进到下一个触发器
    currentTriggerIdx++
    if (currentTriggerIdx > triggerNames.Length())
        currentTriggerIdx := 1

    gosub, UpdateStatusDisplay
return

; 切换启停
ToggleAutomation:
    isRunning := !isRunning
    if (isRunning)
    {
        ; 如果启动热键是Capslock, 关闭Capslock状态避免影响输入
        if (startHotkey = "Capslock" || startHotkey = "CapsLock")
            SetCapsLockState, Off

        ; 重置顺序执行状态（从头开始）
        currentTriggerIdx := 1
        waitUntilTick := 0

        ; 重置所有冷却
        for idx, tName in triggerNames
            triggers[tName].lastTriggered := 0
        lastFireTime := 0
        lastFireName := ""
    }
    gosub, UpdateStatusDisplay
return

; ============================================================
;  T6: 取色工具(鼠标跟随取色)
; ============================================================
; 启动取色模式
; 调用前设置: pickTargetGui, pickTargetX, pickTargetY, pickTargetColor, pickReturnLabel
StartColorPicker:
    if isPicking
        return

    isPicking := 1
    ; 隐藏所有GUI
    if WinExist("freekey — 配置面板")
        Gui, Config:Hide
    Gui, Editor:Hide

    SetTimer, ColorPickerLoop, 30
    MouseGetPos, mX0, mY0
    ToolTip, 取色模式已启动`n移动鼠标到目标位置`nF9 → 确认取色`n右键/Esc → 取消, % mX0+100, % mY0
return

ColorPickerLoop:
    if !isPicking
    {
        SetTimer, ColorPickerLoop, Off
        return
    }

    MouseGetPos, mX, mY, mWin
    color := GetPixelColor(mX, mY)

    ; 取色提示(每帧显示)
    ToolTip,  取色模式 — 鼠标跟随取色
    (
    `n坐标: X=%mX%  Y=%mY%
    `n颜色: #%color%
    `n----------------------------
    `nF9 → 确认取色
    `n右键/Esc → 取消
    ), % mX+100, % mY

    ; 检测F9确认
    if GetKeyState("F9", "P")
    {
        KeyWait, F9
        pickedX := mX
        pickedY := mY
        pickedColor := color
        gosub, ColorPickerDone
        return
    }

    if GetKeyState("RButton", "P")
    {
        KeyWait, RButton
        gosub, ColorPickerCancel
        return
    }

    if GetKeyState("Escape", "P")
    {
        KeyWait, Escape
        gosub, ColorPickerCancel
        return
    }
return

ColorPickerDone:
    isPicking := 0
    SetTimer, ColorPickerLoop, Off
    ToolTip
    SoundBeep, 800, 150

    ; 将取色结果填入目标GUI
    if (pickTargetGui != "" && pickTargetX != "")
    {
        GuiControl, %pickTargetGui%:, %pickTargetX%, %pickedX%
    }
    if (pickTargetGui != "" && pickTargetY != "")
    {
        GuiControl, %pickTargetGui%:, %pickTargetY%, %pickedY%
    }
    if (pickTargetGui != "" && pickTargetColor != "")
    {
        GuiControl, %pickTargetGui%:, %pickTargetColor%, %pickedColor%
    }

    ; 恢复GUI（配置面板不激活，编辑器保持焦点）
    Gui, Config:Show, NoActivate
    Gui, Editor:Show, AutoSize Center

    ; 清空目标
    pickTargetGui := ""
    pickTargetX := ""
    pickTargetY := ""
    pickTargetColor := ""
return

ColorPickerCancel:
    isPicking := 0
    SetTimer, ColorPickerLoop, Off
    ToolTip
    SoundBeep, 400, 100

    ; 恢复GUI（配置面板不激活，编辑器保持焦点）
    Gui, Config:Show, NoActivate
    Gui, Editor:Show, AutoSize Center

    pickTargetGui := ""
    pickTargetX := ""
    pickTargetY := ""
    pickTargetColor := ""
return

; ============================================================
;  T7: 配置GUI面板
; ============================================================
ShowConfigPanel:
    if isPicking
        return

    ; 如果窗口已存在, 激活它
    if WinExist("freekey — 配置面板")
    {
        WinActivate
        return
    }

    ; 创建主窗口 — 使用Tab控件
    Gui, Config:New, +Resize , freekey — 配置面板
    Gui, Config:Add, Tab3, vConfigTab gConfigTabSwitch, 触发器列表|全局设置
 
    ; ====== Tab1: 触发器列表 ======
    Gui, Tab, 1
    Gui, Config:Add, ListView, vTriggerList r15 w560 gTriggerListViewEvent Checked Grid
        , 名称|按键|坐标X|坐标Y|颜色|色差|延迟(ms)|启用

    ; 填充数据
    gosub, RefreshTriggerList

    ; 平均分配列宽: 表格宽度 / 列数
    Gui, Config:Default
    colEqWidth := 560 // 8
    Loop, 8
        LV_ModifyCol(A_Index, colEqWidth)

    ; 按钮行
    Gui, Config:Add, Button, x10 y+10 gAddTrigger, 添加
    Gui, Config:Add, Button, x+5 gEditTrigger, 编辑
    Gui, Config:Add, Button, x+5 gDeleteTrigger, 删除
    Gui, Config:Add, Button, x+5 gMoveTriggerUp, 上移
    Gui, Config:Add, Button, x+5 gMoveTriggerDown, 下移
    Gui, Config:Add, Button, x+30 gSaveAndReload, 保存并重载

    ; ====== Tab2: 全局设置 ======
    Gui, Tab, 2
    ; 按钮放在最前面创建（确保它是第一个可聚焦控件），先隐藏稍后定位
    Gui, Config:Add, Button, x10 y10 vBtnSaveGlobalSettings gSaveGlobalSettings Default Hidden, 保存设置
    GuiControlGet, g_btnSaveHwnd, Hwnd, BtnSaveGlobalSettings  ; 缓存按钮句柄

    ; 热键设置
    Gui, Config:Add, GroupBox, x10 y10 w300 h150, 热键设置
    Gui, Config:Add, Text, x20 yp+25, 启动/停止:
    Gui, Config:Add, Hotkey, x+5 w100 vEditStartHotkey, %startHotkey%
    Gui, Config:Add, Text, x20 y+10, 面板热键:
    Gui, Config:Add, Hotkey, x+5 w100 vEditPanelHotkey, %panelHotkey%

    ; 循环设置
    Gui, Config:Add, GroupBox, x10 y+20 w300 h120, 循环设置
    Gui, Config:Add, Text, x20 yp+25, 检测间隔(ms):
    Gui, Config:Add, Edit, x+5 w60 vEditLoopInterval, %loopInterval%
    Gui, Config:Add, Text, x+5, (10-1000)

    ; 将按钮移到"循环设置"GroupBox下方 15px 处并显示
    GuiControlGet, lp, Pos, EditLoopInterval
    btnY := lpY + lpH + 15
    GuiControl, Move, BtnSaveGlobalSettings, x10 y%btnY%
    GuiControl, Show, BtnSaveGlobalSettings

    Gui, Tab
    Gui, Config:Show, AutoSize Center
return

; 刷新触发器列表
RefreshTriggerList:
    Gui, Config:Default
    GuiControl, -Redraw, TriggerList
    LV_Delete()

    for idx, tName in triggerNames
    {
        trig := triggers[tName]
        if (trig.enabled)
            LV_Add("Check", trig.name, trig.key, trig.x, trig.y
                , trig.color, trig.variation, trig.minInterval, "是")
        else
            LV_Add("", trig.name, trig.key, trig.x, trig.y
                , trig.color, trig.variation, trig.minInterval, "否")
    }

    ; 更新按钮文本
    GuiControl, Config:, ToggleAutoFromPanel, % isRunning ? "■ 停止" : "▶ 启动"
    GuiControl, +Redraw, TriggerList
return

; Tab切换事件
ConfigTabSwitch:
    ; 按钮在 Tab 2 中创建顺序排第一，对话框管理器会自动聚焦到它
return

; ListView事件
TriggerListViewEvent:
    if (A_GuiEvent = "DoubleClick")
    {
        gosub, EditTrigger
    }
    if (A_GuiEvent = "I")  ; 行选中变化
    {
        ; 可以在这里更新按钮状态
    }
return

; 添加触发器
AddTrigger:
    ; 清空临时变量
    editTrgName := ""
    editTrgKey := "1"
    editTrgX := 0
    editTrgY := 0
    editTrgColor := "FFFFFF"
    editTrgVariation := 0
    editTrgMinInterval := 500
    editTrgEnabled := 1
    editIsNew := 1
    gosub, ShowTriggerEditor
return

; 编辑触发器
EditTrigger:
    rowNum := LV_GetNext(0, "Focused")
    if (rowNum = 0)
    {
        SoundBeep, 300, 100
        return
    }

    LV_GetText(editName, rowNum, 1)
    editTrgName := editName
    trig := triggers[editName]

    editTrgKey := trig.key
    editTrgX := trig.x
    editTrgY := trig.y
    editTrgColor := trig.color
    editTrgVariation := trig.variation
    editTrgMinInterval := trig.minInterval
    editTrgEnabled := trig.enabled
    editIsNew := 0
    gosub, ShowTriggerEditor
return

; 删除触发器
DeleteTrigger:
    rowNum := LV_GetNext(0, "Focused")
    if (rowNum = 0)
    {
        SoundBeep, 300, 100
        return
    }

    LV_GetText(delName, rowNum, 1)
    MsgBox, 0x24, 确认删除, 确定要删除触发器 "%delName%" 吗?
    IfMsgBox, Yes
    {
        ; 从数组和对象中删除
        triggers.Delete(delName)
        newNames := []
        for idx, tName in triggerNames
        {
            if (tName != delName)
                newNames.Push(tName)
        }
        triggerNames := newNames
        triggerCount := triggerNames.Length()

        ; 删除INI中对应的节，避免残留
        IniDelete, %CONFIG_PATH%, %delName%

        ; 写入INI
        gosub, WriteConfig
        gosub, RefreshTriggerList
    }
return



; 上移
MoveTriggerUp:
    rowNum := LV_GetNext(0, "Focused")
    if (rowNum <= 1)
        return

    ; 交换位置
    tName := triggerNames[rowNum]
    triggerNames[rowNum] := triggerNames[rowNum - 1]
    triggerNames[rowNum - 1] := tName

    gosub, WriteConfig
    gosub, RefreshTriggerList
    LV_Modify(rowNum - 1, "Select Focus")
return

; 下移
MoveTriggerDown:
    rowNum := LV_GetNext(0, "Focused")
    if (rowNum = 0 || rowNum >= triggerNames.Length())
        return

    tName := triggerNames[rowNum]
    triggerNames[rowNum] := triggerNames[rowNum + 1]
    triggerNames[rowNum + 1] := tName

    gosub, WriteConfig
    gosub, RefreshTriggerList
    LV_Modify(rowNum + 1, "Select Focus")
return

; 从面板启动/停止
ToggleAutoFromPanel:
    gosub, ToggleAutomation
    GuiControl, Config:, ToggleAutoFromPanel, % isRunning ? "■ 停止" : "▶ 启动"
    gosub, UpdateStatusDisplay
return

; 保存并重载
SaveAndReload:
    ; 如果编辑器已打开, 先保存编辑器中的触发器修改
    if WinExist("触发器编辑")
        gosub, SaveTriggerEditor
    gosub, SaveGlobalSettings
    gosub, WriteConfig
    Reload
return

; ============================================================
;  触发器编辑器GUI
; ============================================================
ShowTriggerEditor:
    ; 如果已存在, 先销毁
    Gui, Editor:Destroy

    Gui, Editor:New, +AlwaysOnTop +OwnerConfig, 触发器编辑

    Gui, Editor:Add, GroupBox, x10 y10 w350 h60, 基本信息
    Gui, Editor:Add, Text, x20 yp+25, 名称:
    Gui, Editor:Add, Edit, x+5 w200 vEditName, %editTrgName%
    Gui, Editor:Add, Text, x20 y+10, 按键:
    Gui, Editor:Add, Hotkey, x+5 w100 vEditKey, %editTrgKey%

    Gui, Editor:Add, GroupBox, x10 y+10 w350 h100, 颜色检测(单点模式)
    Gui, Editor:Add, Text, x20 yp+25, 坐标X:
    Gui, Editor:Add, Edit, x+5 w50 vEditX, %editTrgX%
    Gui, Editor:Add, Button, x+5 gPickX, 取色
    Gui, Editor:Add, Text, x20 y+8, 坐标Y:
    Gui, Editor:Add, Edit, x+5 w50 vEditY, %editTrgY%
    Gui, Editor:Add, Text, x20 y+8, 颜色(#):
    Gui, Editor:Add, Edit, x+5 w80 vEditColor, %editTrgColor%
    Gui, Editor:Add, Text, x20 y+8, 色差(0-255):
    Gui, Editor:Add, Edit, x+5 w50 vEditVariation, %editTrgVariation%

    Gui, Editor:Add, GroupBox, x10 y+10 w350 h80, 延迟设置
    Gui, Editor:Add, Text, x20 yp+25, 延迟(ms):
    Gui, Editor:Add, Edit, x+5 w60 vEditMinInterval, %editTrgMinInterval%
    Gui, Editor:Add, Text, x+5, (防止连发)
    if (editTrgEnabled)
        Gui, Editor:Add, CheckBox, x20 y+10 vEditEnabled Checked, 启用
    else
        Gui, Editor:Add, CheckBox, x20 y+10 vEditEnabled, 启用

    ; 按钮
    Gui, Editor:Add, Button, x90 y+20 w80 gSaveTriggerEditor, 保存
    Gui, Editor:Add, Button, x+10 w80 gCancelTriggerEditor, 取消

    Gui, Editor:Show, AutoSize Center
return

; 取色按钮(单点X)
PickX:
    Gui, Editor:Submit, NoHide
    pickTargetGui := "Editor"
    pickTargetX := "EditX"
    pickTargetY := "EditY"
    pickTargetColor := "EditColor"
    gosub, StartColorPicker
return

; 保存触发器编辑器
SaveTriggerEditor:
    Gui, Editor:Submit, NoHide

    ; 验证输入
    if (EditName = "")
    {
        MsgBox, 0x30, 提示, 请输入触发器名称!
        return
    }

    ; 格式化颜色
    EditColor := FormatColor(EditColor)

    ; 创建/更新触发器对象
    trig := Object()
    trig.name := EditName
    trig.key := EditKey
    trig.x := EditX + 0
    trig.y := EditY + 0
    trig.color := EditColor
    trig.variation := EditVariation + 0
    trig.minInterval := EditMinInterval + 0
    trig.enabled := EditEnabled ? 1 : 0
    trig.lastTriggered := 0

    if (trig.minInterval < 0)
        trig.minInterval := 0

    if (editIsNew)
    {
        ; 新建
        if triggers.HasKey(EditName)
        {
            MsgBox, 0x30, 提示, 名称 "%EditName%" 已存在!
            return
        }
        triggers[EditName] := trig
        triggerNames.Push(EditName)
    }
    else
    {
        ; 编辑 — 如果名称变了, 需要处理
        if (EditName != editTrgName)
        {
            triggers.Delete(editTrgName)
            triggers[EditName] := trig
            ; 更新名称列表
            for idx, tName in triggerNames
            {
                if (tName = editTrgName)
                {
                    triggerNames[idx] := EditName
                    break
                }
            }
            ; 删除旧名称的 INI 节，避免残留混淆
            IniDelete, %CONFIG_PATH%, %editTrgName%
        }
        else
        {
            triggers[EditName] := trig
        }
    }
    triggerCount := triggerNames.Length()

    ; 写入INI
    gosub, WriteConfig
    gosub, RefreshTriggerList

    Gui, Editor:Destroy
return

CancelTriggerEditor:
    Gui, Editor:Destroy
return

; ============================================================
;  全局设置功能
; ============================================================
SaveGlobalSettings:
    Gui, Config:Submit, NoHide

    ; 热键设置 — 验证
    conflictMsg := ""

    if (EditStartHotkey != startHotkey)
    {
        Hotkey, %startHotkey%, ToggleAutomation, Off
        Hotkey, %EditStartHotkey%, ToggleAutomation, On
        startHotkey := EditStartHotkey
    }

    if (EditPanelHotkey != panelHotkey)
    {
        Hotkey, %panelHotkey%, ShowConfigPanel, Off
        Hotkey, %EditPanelHotkey%, ShowConfigPanel, On
        panelHotkey := EditPanelHotkey
    }

    ; 循环设置
    newInterval := EditLoopInterval + 0
    if (newInterval < 10)
        newInterval := 10
    if (newInterval > 1000)
        newInterval := 1000
    if (newInterval != loopInterval)
    {
        loopInterval := newInterval
        SetTimer, MainLoop, %loopInterval%
    }

    ; 保存到INI
    gosub, WriteConfig
    SoundBeep, 600, 100

    ; 更新状态
    gosub, UpdateStatusDisplay
return


; ============================================================
;  T8: 热键系统
; ============================================================
RegisterHotkeys:
    ; 使用动态热键注册, 避免冲突
    Hotkey, %startHotkey%, ToggleAutomation, On UseErrorLevel
    if (ErrorLevel)
        MsgBox, 0x30, 热键冲突, 启动热键 %startHotkey% 注册失败!

    Hotkey, %panelHotkey%, ShowConfigPanel, On UseErrorLevel
    if (ErrorLevel)
        MsgBox, 0x30, 热键冲突, 面板热键 %panelHotkey% 注册失败!
return

; ============================================================
;  状态显示
; ============================================================
UpdateStatusDisplay:
    ; 获取当前激活窗口位置（顶部中心）
    WinGetPos, wx, wy, ww, wh, A
    tipX := wx + ww//2 - 70
    tipY := wy + 5

    if (isRunning)
    {
        statusText := "▶ 运行中"
        statusText .= "`n触发器: " . triggerCount . " 个"
        statusText .= "`n间隔: " . loopInterval . "ms"

        if (lastFireName != "" && A_TickCount - lastFireTime < 2000)
        {
            statusText .= "`n最近触发: " . lastFireName
        }

        ToolTip, %statusText%, %tipX%, %tipY%
    }
    else
    {
        if (triggerCount > 0)
        {
            ToolTip
        }
        else
        {
            ToolTip, ● 已停止 (无触发器), %tipX%, %tipY%
        }
    }
return

; ============================================================
;  退出处理
; ============================================================
ExitSub:
    ; 保存配置
    gosub, WriteConfig

    ; 清理
    ToolTip
    SoundBeep, 400, 100

    ; 停止所有定时器
    SetTimer, MainLoop, Off
    SetTimer, ColorPickerLoop, Off
ExitApp

; ============================================================
;  GUI 事件
; ============================================================
ConfigGuiClose:
    if WinExist("触发器编辑")
        gosub, SaveTriggerEditor
    gosub, SaveGlobalSettings
    gosub, WriteConfig
    Gui, Config:Destroy
return

ConfigGuiEscape:
    Gui, Config:Destroy
return

EditorGuiClose:
    Gui, Editor:Destroy
return

EditorGuiEscape:
    Gui, Editor:Destroy
return

; ============================================================
;  结束
; ============================================================
