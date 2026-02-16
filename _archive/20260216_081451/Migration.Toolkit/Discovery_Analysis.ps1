$moduleRoot = "C:\Users\paull\OneDrive - Paul Lagana\Documents\GitHub\lc-toolkit\src\Lagana.Consulting.Toolkit"
Remove-Module Lagana.Consulting.Toolkit -ErrorAction SilentlyContinue
Import-Module "$moduleRoot\Lagana.Consulting.Toolkit.psd1" -Force

Invoke-AdDiscoveryAnalysis -ConfigFile 'C:\Users\paull\OneDrive - Paul Lagana\Documents\GitHub\lc-toolkit\src\Lagana.Consulting.Toolkit\config\Config_MultiSource_Test.json'

