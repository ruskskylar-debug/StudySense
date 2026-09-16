import os
import re

from PyPDF2 import PdfReader
from docx import Document


def readTextFile(filePath):
    with open(filePath, "r", encoding="utf-8") as file:
        return file.read()


def readPdfFile(filePath):
    reader = PdfReader(filePath)

    text = ""

    for page in reader.pages:
        pageText = page.extract_text()

        if pageText:
            text += pageText + "\n"

    return text


def readDocxFile(filePath):
    document = Document(filePath)

    text = ""

    for paragraph in document.paragraphs:
        text += paragraph.text + "\n"

    return text


def readFile(filePath):
    fileExtension = os.path.splitext(filePath)[1].lower()

    if fileExtension == ".txt":
        return readTextFile(filePath)

    elif fileExtension == ".pdf":
        return readPdfFile(filePath)

    elif fileExtension == ".docx":
        return readDocxFile(filePath)

    else:
        print("File type not supported.")
        return ""


def cleanText(text):
    text = re.sub(r"[ \t]+", " ", text)

    text = re.sub(
        r"\n\s*\n+",
        "\n\n",
        text
    )

    text = text.strip()

    return text
