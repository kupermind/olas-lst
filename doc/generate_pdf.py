#!/usr/bin/env python3
"""
Script to generate PDF from stOLAS whitepaper text file
Requires: pip install reportlab
"""

import os
from reportlab.lib.pagesizes import letter, A4
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_JUSTIFY
from reportlab.lib.colors import black, darkblue, darkgreen

def create_pdf(input_file, output_file):
    """Create PDF from text file"""
    
    # Create PDF document
    doc = SimpleDocTemplate(output_file, pagesize=A4,
                          rightMargin=72, leftMargin=72,
                          topMargin=72, bottomMargin=72)
    
    # Get styles
    styles = getSampleStyleSheet()
    
    # Custom styles
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Heading1'],
        fontSize=24,
        spaceAfter=30,
        alignment=TA_CENTER,
        textColor=darkblue
    )
    
    heading1_style = ParagraphStyle(
        'CustomHeading1',
        parent=styles['Heading1'],
        fontSize=18,
        spaceAfter=12,
        spaceBefore=20,
        textColor=darkblue
    )
    
    heading2_style = ParagraphStyle(
        'CustomHeading2',
        parent=styles['Heading2'],
        fontSize=14,
        spaceAfter=8,
        spaceBefore=16,
        textColor=darkgreen
    )
    
    body_style = ParagraphStyle(
        'CustomBody',
        parent=styles['Normal'],
        fontSize=11,
        spaceAfter=6,
        alignment=TA_JUSTIFY
    )
    
    # Build story
    story = []
    
    # Read input file
    with open(input_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Split into sections
    sections = content.split('\n\n')
    
    for section in sections:
        section = section.strip()
        if not section:
            continue
            
        # Check if it's a title
        if section.startswith('Disclaimer'):
            story.append(Paragraph(section, title_style))
            story.append(Spacer(1, 20))
        elif section.startswith('Executive Summary'):
            story.append(Paragraph(section, title_style))
            story.append(Spacer(1, 20))
        elif section.startswith('Introduction to stOLAS'):
            story.append(Paragraph(section, title_style))
            story.append(Spacer(1, 20))
        elif section.startswith('Token Utility'):
            story.append(Paragraph(section, heading1_style))
        elif section.startswith('Architecture'):
            story.append(Paragraph(section, heading1_style))
        elif section.startswith('Technical'):
            story.append(Paragraph(section, heading1_style))
        elif section.startswith('DeFi Integration'):
            story.append(Paragraph(section, heading1_style))
        elif section.startswith('Security'):
            story.append(Paragraph(section, heading1_style))
        elif section.startswith('Governance'):
            story.append(Paragraph(section, heading1_style))
        elif section.startswith('Roadmap'):
            story.append(Paragraph(section, heading1_style))
        elif section.startswith('Economic Model'):
            story.append(Paragraph(section, heading1_style))
        elif section.startswith('Risk Factors'):
            story.append(Paragraph(section, heading1_style))
        elif section.startswith('Conclusion'):
            story.append(Paragraph(section, heading1_style))
        elif section.startswith('Glossary'):
            story.append(Paragraph(section, heading1_style))
        elif section.startswith('Contact Information'):
            story.append(Paragraph(section, heading1_style))
        elif section.startswith('**') and section.endswith('**'):
            # Bold text (remove ** and apply heading2 style)
            clean_text = section.replace('**', '')
            story.append(Paragraph(clean_text, heading2_style))
        else:
            # Regular body text
            story.append(Paragraph(section, body_style))
        
        story.append(Spacer(1, 6))
    
    # Build PDF
    doc.build(story)
    print(f"PDF generated successfully: {output_file}")

if __name__ == "__main__":
    input_file = "stolas_whitepaper.txt"
    output_file = "stolas_whitepaper_formatted.pdf"
    
    if not os.path.exists(input_file):
        print(f"Error: Input file '{input_file}' not found!")
        exit(1)
    
    try:
        create_pdf(input_file, output_file)
    except Exception as e:
        print(f"Error generating PDF: {e}")
        exit(1)
