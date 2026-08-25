try (destroyDialog MaxUltraMcpUiAutomationTest) catch ()

rollout MaxUltraMcpUiAutomationTest "Max Ultra MCP UI Automation Test" width:360 height:150
(
    editText inputValue "Value:" pos:[16,18] width:328 text:"before"
    button applyButton "Apply with MCP" pos:[16,55] width:160 height:28
    label resultLabel "Result: not invoked" pos:[16,98] width:328 height:22

    on applyButton pressed do
    (
        resultLabel.text = "Result: " + inputValue.text
        format "[Max Ultra MCP UI Test] %\n" resultLabel.text
    )
)

createDialog MaxUltraMcpUiAutomationTest style:#(#style_titlebar, #style_border, #style_sysmenu)
