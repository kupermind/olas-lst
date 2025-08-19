# stOLAS Documentation

This directory contains the official documentation for the stOLAS project.

## Files

- `stolas_whitepaper.txt` - The main whitepaper in text format
- `stolas_whitepaper_formatted.pdf` - The formatted PDF version of the whitepaper
- `generate_pdf.py` - Python script to generate PDF from text file
- `requirements.txt` - Python dependencies for PDF generation

## Generating PDF

To regenerate the PDF from the text file:

### Prerequisites
```bash
# Install Python dependencies
pip install -r requirements.txt
```

### Generate PDF
```bash
# Run the PDF generation script
python generate_pdf.py
```

The script will read `stolas_whitepaper.txt` and generate `stolas_whitepaper_formatted.pdf`.

## Alternative Methods

If you prefer not to use Python, you can also generate PDF using:

### Pandoc (Markdown to PDF)
```bash
# Convert text to markdown first, then to PDF
pandoc stolas_whitepaper.txt -o stolas_whitepaper_formatted.pdf
```

### LibreOffice
```bash
# Convert text to PDF using LibreOffice
libreoffice --headless --convert-to pdf stolas_whitepaper.txt
```

### Online Tools
- Use online text-to-PDF converters
- Copy text into Google Docs and export as PDF
- Use Microsoft Word to format and export as PDF

## Notes

- The Python script (`generate_pdf.py`) provides the most control over formatting
- The generated PDF includes proper styling, headers, and spacing
- Always review the generated PDF to ensure proper formatting
- Update the text file first, then regenerate the PDF
