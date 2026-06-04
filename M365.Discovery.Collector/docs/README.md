# M365 Discovery Collector - Documentation

Copyright (c) 2024 Lagana Consulting. All rights reserved.

---

## Available Documentation

This folder contains comprehensive documentation for using the M365 Discovery Collector application.

### For End Users (Customers)

#### 📘 [Quick Start Guide](Quick-Start-Guide.md)
**Best for:** Customers who want to get started quickly  
**Length:** 2 pages  
**Content:** Essential steps only, minimal explanation  
**Use when:** Customer is technically comfortable and wants fast results

#### 📗 [User Guide - GUI Collector](User-Guide-GUI-Collector.md)
**Best for:** Comprehensive reference documentation  
**Length:** 12 pages  
**Content:** Complete instructions with explanations, troubleshooting, and details  
**Use when:** Customer needs full documentation or troubleshooting help

#### 📙 [Visual Step-by-Step Guide](Visual-Step-by-Step-Guide.md)
**Best for:** Visual learners or less technical users  
**Length:** 20+ pages with screenshot placeholders  
**Content:** Every step with annotated screenshots  
**Use when:** Customer prefers visual guides or is less technical  
**Note:** Requires screenshots to be captured and added

---

## Recommended Distribution

### Option 1: Send All Three
Provide all guides and let the customer choose based on their preference:
- Quick Start for fast execution
- User Guide for reference
- Visual Guide for detailed walkthrough

### Option 2: Choose Based on Customer
Assess customer's technical level and send appropriate guide:
- **Technical users:** Quick Start Guide
- **Business users:** User Guide
- **Non-technical users:** Visual Step-by-Step Guide

### Option 3: Progressive Documentation
1. Start with **Quick Start Guide**
2. If customer has questions → send **User Guide**
3. If customer needs more help → send **Visual Guide**

---

## Documentation Contents Overview

### Quick Start Guide
- ✅ One-time setup (4 steps)
- ✅ Collection procedure (6 steps)
- ✅ Output location
- ✅ Common issues table
- ⏱️ Read time: 5 minutes

### User Guide (Full)
- ✅ Detailed overview and prerequisites
- ✅ Complete initial setup (7 steps with explanations)
- ✅ Collection procedure (8 detailed steps)
- ✅ Output structure explanation
- ✅ CSV file descriptions
- ✅ Comprehensive troubleshooting
- ✅ Data privacy information
- ⏱️ Read time: 20-30 minutes

### Visual Step-by-Step Guide
- ✅ Screenshot for every major step
- ✅ Annotated images showing what to click
- ✅ "What You Should See" sections
- ✅ Visual troubleshooting examples
- ✅ Button reference table
- ✅ Status indicator legend
- 📷 **Requires screenshots to be added**
- ⏱️ Read time: 10-15 minutes (with images)

---

## Completing the Visual Guide

The Visual Step-by-Step Guide includes placeholder references for 26 screenshots. To complete it:

### 1. Create Screenshots Folder
```
docs/
└── screenshots/
    ├── 01-launch-application.png
    ├── 02-enable-bootstrap-role.png
    └── ... (24 more)
```

### 2. Capture Screenshots
Use Windows Snipping Tool or similar to capture:
- Each button mentioned in the guide
- Dialog boxes and configuration screens
- Progress indicators and status messages
- Success states and error examples

### 3. Annotate Screenshots (Optional)
Use an image editor to:
- Add arrows pointing to buttons
- Highlight relevant areas with colored boxes
- Add text labels for clarity

### 4. Test the Guide
- Give it to a test user
- Have them follow it step-by-step
- Note any confusion points
- Update screenshots and text as needed

---

## Customization Tips

### Branding
- Add your company logo to the header
- Update footer with contact information
- Customize support section with your helpdesk details

### Tenant-Specific Information
- Pre-fill Tenant ID in instructions if known
- Include specific permission requirements for customer's scenario
- Add customer-specific workload recommendations

### Output Examples
- Include sample CSV excerpts showing typical data
- Show example run-metadata.json contents
- Provide sample analysis reports (if available)

---

## Distribution Formats

### Markdown (Current)
- ✅ Easy to edit and version control
- ✅ Can be viewed on GitHub/GitLab
- ❌ Requires markdown viewer for customers

### PDF (Recommended for Customers)
Convert markdown to PDF using:
- **Pandoc:** `pandoc -o guide.pdf guide.md`
- **Markdown to PDF** tools
- **Print to PDF** from markdown viewer

### Word Document
Convert for customers who prefer .docx:
- Open in markdown editor with export
- Use Pandoc with Word template
- Allows customer to annotate

### Web Page
Host as HTML for easy access:
- Use static site generator (Jekyll, Hugo)
- Host on internal portal or GitHub Pages
- Searchable and always up-to-date

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0 | 2024 | Initial documentation for GUI Collector V2 |

---

## Maintenance

### Update When:
- Application UI changes
- New workloads are added
- Authentication flow changes
- Customer feedback identifies gaps
- New troubleshooting scenarios discovered

### Review Schedule:
- **Major releases:** Complete review and update
- **Minor releases:** Check affected sections
- **Quarterly:** Review troubleshooting section based on support tickets
- **Annually:** Full documentation audit

---

## Support Resources

### For Documentation Questions
- Review the application source code for UI elements
- Test the application to verify steps
- Consult with development team for technical details

### For Customer Support
- Keep log of common customer questions
- Add FAQ section based on support tickets
- Create supplementary guides for specific scenarios

---

## Additional Documentation Needed

Consider creating these additional guides:

### For IT Admins
- **Deployment Guide:** How to distribute the application to users
- **Permissions Reference:** Detailed Graph API permission requirements
- **Troubleshooting Guide:** Technical deep-dive for IT support staff

### For Analysts
- **Data Dictionary:** Detailed description of each CSV column
- **Analysis Guide:** How to use the collected data
- **Migration Planning Guide:** Using collector data for migration decisions

### For Developers
- **API Reference:** If exposing any APIs
- **Customization Guide:** How to modify workloads or add collectors
- **Build Instructions:** How to compile and distribute

---

## License and Distribution

**Copyright © 2024 Lagana Consulting. All rights reserved.**

These documentation files are proprietary and may be distributed to customers as part of the M365 Discovery Collector service. 

### Customer Use
- ✅ May be shared with customer's employees
- ✅ May be modified with customer-specific information
- ❌ May not be redistributed outside customer organization
- ❌ May not be used for competing services

---

## Contact

For documentation questions or suggestions:
- Internal: Contact Lagana Consulting development team
- Customers: Contact your Lagana Consulting representative

---

**Last Updated:** 2024
