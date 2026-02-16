remove-module Identity.Security.Assessment.Toolkit
import-module "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Identity.Security.Assessment.Toolkit\src\Identity.Security.Assessment.Toolkit.psd1"


Invoke-IdentitySecurityAssessment `
    -Profile Deep `
    -AzureHoundInputPath 'D:\Bloodhound\azurehound-output.json' `
    -OutputRoot 'd:\bloodhound\output'

