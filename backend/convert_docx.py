import pypandoc
import os

print("Downloading pandoc (if not installed)...")
pypandoc.download_pandoc()

input_file = r'c:\java\GDF\Qurany_Mobile_APP\Documents\Qurany_Final_Documentation_Complete.md'
output_file = r'c:\java\GDF\Qurany_Mobile_APP\Documents\Qurany_Final_Documentation.docx'

print(f"Converting {input_file} to docx...")
pypandoc.convert_file(input_file, 'docx', outputfile=output_file)
print(f"Successfully converted to {output_file}")
