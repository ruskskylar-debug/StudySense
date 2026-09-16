from flask import Flask, render_template, request, redirect, url_for
import os
import json
import re

from src.dataInput import readFile, cleanText


app = Flask(__name__)
app.secret_key = "studysense-secret-key"


DATA_FILE = "data/studyData.json"


# --------------------------------------------------
# LOAD AI MODEL ONCE
# --------------------------------------------------

print("Loading StudySense AI...")

try:
    from transformers import pipeline

    llm = pipeline(
        "text-generation",
        model="Qwen/Qwen2.5-1.5B-Instruct",
        device_map="auto"
    )

    print("StudySense AI is ready.")

    

except Exception as error:

    llm = None

    print("StudySense AI could not be loaded.")
    print(error)

    


# --------------------------------------------------
# DATA FUNCTIONS
# --------------------------------------------------

def loadStudyData():

    if not os.path.exists(DATA_FILE):
        return {
            "subjects": {}
        }

    with open(
        DATA_FILE,
        "r",
        encoding="utf-8"
    ) as file:

        return json.load(file)


def saveStudyData(data):

    os.makedirs(
        "data",
        exist_ok=True
    )

    with open(
        DATA_FILE,
        "w",
        encoding="utf-8"
    ) as file:

        json.dump(
            data,
            file,
            indent=4
        )


def getSubjectNames():

    data = loadStudyData()

    return list(
        data["subjects"].keys()
    )


def saveMaterial(
    subject,
    topic,
    text,
    fileName
):

    data = loadStudyData()

    if subject not in data["subjects"]:

        data["subjects"][subject] = {
            "materials": [],
            "weakPoints": [],
            "studySessions": [],
            "flashcardResults": []
        }

    data["subjects"][subject].setdefault(
        "materials",
        []
    )

    data["subjects"][subject].setdefault(
        "weakPoints",
        []
    )

    data["subjects"][subject].setdefault(
        "studySessions",
        []
    )

    data["subjects"][subject].setdefault(
        "flashcardResults",
        []
    )

    material = {
        "topic": topic,
        "fileName": fileName,
        "text": text
    }

    data["subjects"][subject]["materials"].append(
        material
    )

    saveStudyData(data)


def getSubjectMaterialText(subject):

    data = loadStudyData()

    if subject not in data["subjects"]:
        return ""

    allText = ""

    for material in data["subjects"][subject]["materials"]:

        allText += "\n\n"
        allText += material["text"]

    return allText


# --------------------------------------------------
# HOME
# --------------------------------------------------

@app.route("/")
def home():

    data = loadStudyData()

    return render_template(
        "home.html",
        subjects=data["subjects"]
    )


# --------------------------------------------------
# UPLOAD MATERIAL
# --------------------------------------------------

@app.route(
    "/upload",
    methods=["POST"]
)
def upload():

    subject = request.form.get(
        "subject"
    )

    topic = request.form.get(
        "topic"
    )

    if not topic or topic.strip() == "":
        topic = "General"

    uploadedFile = request.files.get(
        "file"
    )

    if not subject:

        return "Please enter a subject."

    if (
        uploadedFile
        and uploadedFile.filename != ""
    ):

        os.makedirs(
            "data/raw",
            exist_ok=True
        )

        fileName = uploadedFile.filename

        filePath = os.path.join(
            "data/raw",
            fileName
        )

        uploadedFile.save(
            filePath
        )

        text = readFile(
            filePath
        )

        if text == "":
            return "Unable to read this file."

        cleanedText = cleanText(
            text
        )

        os.makedirs(
            "data/cleaned",
            exist_ok=True
        )

        cleanedFileName = (
            fileName.rsplit(
                ".",
                1
            )[0]
            + "_cleaned.txt"
        )

        cleanedFilePath = os.path.join(
            "data/cleaned",
            cleanedFileName
        )

        with open(
            cleanedFilePath,
            "w",
            encoding="utf-8"
        ) as file:

            file.write(
                cleanedText
            )

        saveMaterial(
            subject,
            topic,
            cleanedText,
            fileName
        )

        return redirect(
            url_for("home")
        )

    text = request.form.get(
        "text"
    )

    if (
        text
        and text.strip() != ""
    ):

        cleanedText = cleanText(
            text
        )

        saveMaterial(
            subject,
            topic,
            cleanedText,
            "Text Input"
        )

        return redirect(
            url_for("home")
        )

    return "Please upload a file or enter text."


# --------------------------------------------------
# ASK AI
# --------------------------------------------------

@app.route(
    "/ask-ai",
    methods=["GET"]
)
def askAI():

    data = loadStudyData()

    selectedSubject = request.args.get(
        "subject",
        ""
    )

    materials = []

    if selectedSubject in data["subjects"]:

        materials = data["subjects"][
            selectedSubject
        ]["materials"]

    return render_template(
        "askAI.html",
        subjects=data["subjects"],
        materials=materials,
        selectedSubject=selectedSubject
    )


@app.route(
    "/ask-ai",
    methods=["POST"]
)
def answerQuestion():

    question = request.form.get(
        "question"
    )

    subject = request.form.get(
        "subject"
    )

    data = loadStudyData()

    materialText = getSubjectMaterialText(
        subject
    )

    answer = generateAnswer(
        materialText,
        question
    )

    materials = []

    if subject in data["subjects"]:

        materials = data["subjects"][
            subject
        ]["materials"]

    return render_template(
        "askAI.html",
        subjects=data["subjects"],
        materials=materials,
        selectedSubject=subject,
        question=question,
        answer=answer
    )


def findRelevantMaterial(text, question, maxCharacters=3500):

    sections = []

    for paragraph in text.split("\n\n"):
        paragraph = paragraph.strip()
        if paragraph:
            sections.append(paragraph)

    if not sections:
        return text[:maxCharacters]

    questionWords = set(re.findall(r"\b[a-zA-Z]{3,}\b", question.lower()))
    scoredSections = []

    for section in sections:
        sectionWords = set(re.findall(r"\b[a-zA-Z]{3,}\b", section.lower()))
        score = len(questionWords.intersection(sectionWords))
        scoredSections.append((score, section))

    scoredSections.sort(key=lambda item: item[0], reverse=True)

    relevantText = ""

    for score, section in scoredSections:
        if score == 0 and relevantText:
            continue
        if len(relevantText) + len(section) > maxCharacters:
            break
        relevantText += section + "\n\n"

    if relevantText.strip() == "":
        relevantText = text[:maxCharacters]

    return relevantText[:maxCharacters]


def generateAnswer(text, question):

    if text.strip() == "":
        return "There is no study material for this subject yet."

    if llm is None:
        return "StudySense AI could not be loaded. Check the terminal for the AI error."

    try:

        relevantText = findRelevantMaterial(
            text,
            question,
            1500
        )

        prompt = f"""
You are StudySense.

Answer the student's question using ONLY the study material below.

Rules:
- Use only information from the study material.
- Do not use outside knowledge.
- If the answer is not found in the study material, say:
  "I cannot find that information in the study material."
- Keep the answer clear and concise.

Study Material:
{relevantText}

Question:
{question}

Answer:
"""

        result = llm(
            prompt,
            max_new_tokens=150,
            do_sample=False
        )

        answer = result[0]["generated_text"]

        if "Answer:" in answer:
            answer = answer.split("Answer:")[-1].strip()

        return answer

    except Exception as error:

        return "StudySense could not generate an answer.\n\n" + str(error)

# --------------------------------------------------
# FLASHCARDS
# --------------------------------------------------


@app.route(
    "/flashcards",
    methods=["GET"]
)
def flashcards():

    data = loadStudyData()

    selectedSubject = request.args.get(
        "subject",
        ""
    )

    materials = []
    weakPoints = []

    if selectedSubject in data["subjects"]:

        subjectData = data["subjects"][
            selectedSubject
        ]

        materials = subjectData.get(
            "materials",
            []
        )

        weakPoints = subjectData.get(
            "weakPoints",
            []
        )

    return render_template(
        "flashcards.html",
        subjects=data["subjects"],
        materials=materials,
        weakPoints=weakPoints,
        selectedSubject=selectedSubject
    )


@app.route(
    "/flashcards",
    methods=["POST"]
)
def createFlashcards():

    choice = request.form.get(
        "choice"
    )

    subject = request.form.get(
        "subject"
    )

    topic = request.form.get(
        "topic"
    )

    number = request.form.get(
        "number"
    )

    try:
        number = min(int(number), 20)
    except:
        number = 10

    data = loadStudyData()

    if subject not in data["subjects"]:

        return render_template(
            "flashcards.html",
            subjects=data["subjects"],
            materials=[],
            weakPoints=[],
            selectedSubject="",
            error="Please choose a subject first."
        )

    subjectData = data["subjects"][
        subject
    ]

    subjectData.setdefault(
        "materials",
        []
    )

    subjectData.setdefault(
        "weakPoints",
        []
    )

    subjectData.setdefault(
        "flashcardResults",
        []
    )

    materialText = ""

    if choice == "all":

        for material in subjectData["materials"]:

            materialText += (
                material["text"]
                + "\n"
            )

    elif choice == "topic":

        if not topic:
            topic = ""

        for material in subjectData["materials"]:

            if (
                material["topic"].lower()
                == topic.lower()
            ):

                materialText += (
                    material["text"]
                    + "\n"
                )

    elif choice == "weak":

        for weakPoint in subjectData["weakPoints"]:

            materialText += (
                weakPoint
                + "\n"
            )

    elif choice == "random":

        for material in subjectData["materials"]:

            materialText += (
                material["text"]
                + "\n"
            )

    if materialText.strip() == "":

        return render_template(
            "flashcards.html",
            subjects=data["subjects"],
            materials=subjectData["materials"],
            weakPoints=subjectData["weakPoints"],
            selectedSubject=subject,
            error="There is not enough study material for this subject yet."
        )

    cards = generateFlashcards(
        materialText,
        number
    )

    return render_template(
        "flashcards.html",
        subjects=data["subjects"],
        materials=subjectData["materials"],
        weakPoints=subjectData["weakPoints"],
        selectedSubject=subject,
        cards=cards
    )


def generateFlashcards(text, number):

    if llm is None:
        return [{
            "question": "Flashcards could not be generated.",
            "answer": "StudySense AI could not be loaded. Check the terminal."
        }]

    try:

        relevantText = findRelevantMaterial(
            text,
            "important concepts definitions facts",
            1500
        )

        prompt = f"""
You are StudySense.

Create exactly {number} flashcards using ONLY the study material below.

Rules:
- Use information only from the study material.
- Do not use outside knowledge.
- Each flashcard must have one QUESTION and one ANSWER.
- Do not add explanations before or after the flashcards.

Format exactly like this:

QUESTION: question text
ANSWER: answer text

QUESTION: question text
ANSWER: answer text

Study Material:
{relevantText}
"""

        result = llm(
            prompt,
            max_new_tokens=600,
            do_sample=False
        )

        generatedText = result[0]["generated_text"]

        print("\n----- AI OUTPUT -----")
        print(generatedText)
        print("----- END OUTPUT -----\n")

        cards = parseFlashcards(
            generatedText
        )[:number]

        if cards:
            return cards

        return [{
            "question": "The AI generated an unexpected format.",
            "answer": generatedText
        }]

    except Exception as error:

        return [{
            "question": "Flashcards could not be generated.",
            "answer": str(error)
        }]


def parseFlashcards(text):

    cards = []

    question = None
    answer = None

    lines = text.splitlines()

    for line in lines:

        line = line.strip()

        if line == "":
            continue

        if line.upper().startswith(
            "QUESTION:"
        ):

            if question and answer:

                cards.append(
                    {
                        "question": question,
                        "answer": answer
                    }
                )

            question = line.split(
                ":",
                1
            )[1].strip()

            answer = None

        elif line.upper().startswith(
            "ANSWER:"
        ):

            if question:

                answer = line.split(
                    ":",
                    1
                )[1].strip()

    if question and answer:

        cards.append(
            {
                "question": question,
                "answer": answer
            }
        )

    return cards
# --------------------------------------------------
# FLASHCARD RESULTS
# --------------------------------------------------

@app.route(
    "/flashcard-result",
    methods=["POST"]
)
def flashcardResult():

    subject = request.form.get(
        "subject"
    )

    question = request.form.get(
        "question"
    )

    result = request.form.get(
        "result"
    )

    data = loadStudyData()

    if subject not in data["subjects"]:

        return redirect(
            url_for("flashcards")
        )

    if result not in [
        "gotIt",
        "almost",
        "needHelp"
    ]:

        return redirect(
            url_for(
                "flashcards",
                subject=subject
            )
        )

    data["subjects"][subject].setdefault(
        "flashcardResults",
        []
    )

    data["subjects"][subject].setdefault(
        "weakPoints",
        []
    )

    flashcardResultData = {
        "question": question,
        "result": result
    }

    data["subjects"][subject][
        "flashcardResults"
    ].append(
        flashcardResultData
    )

    if result == "needHelp":

        if (
            question
            not in data["subjects"][subject]["weakPoints"]
        ):

            data["subjects"][subject][
                "weakPoints"
            ].append(
                question
            )

    saveStudyData(
        data
    )

    return redirect(
        url_for(
            "progress",
            subject=subject
        )
    )


# --------------------------------------------------
# PROGRESS
# --------------------------------------------------

@app.route("/progress")
def progress():

    data = loadStudyData()

    selectedSubject = request.args.get(
        "subject",
        ""
    )

    materials = []
    weakPoints = []
    flashcardResults = []

    if selectedSubject in data["subjects"]:

        subjectData = data["subjects"][
            selectedSubject
        ]

        materials = subjectData.get(
            "materials",
            []
        )

        weakPoints = subjectData.get(
            "weakPoints",
            []
        )

        flashcardResults = subjectData.get(
            "flashcardResults",
            []
        )

    totalResults = len(
        flashcardResults
    )

    progressPercent = 0

    if totalResults > 0:

        gotItCount = 0

        for result in flashcardResults:

            if result["result"] == "gotIt":

                gotItCount += 1

            elif result["result"] == "almost":

                gotItCount += 0.5

        progressPercent = round(
            (gotItCount / totalResults)
            * 100
        )

    return render_template(
        "progress.html",
        subjects=data["subjects"],
        materials=materials,
        weakPoints=weakPoints,
        selectedSubject=selectedSubject,
        progressPercent=progressPercent,
        flashcardResults=flashcardResults
    )


# --------------------------------------------------
# ADD WEAK POINT
# --------------------------------------------------

@app.route(
    "/add-weak-point",
    methods=["POST"]
)
def addWeakPoint():

    subject = request.form.get(
        "subject"
    )

    weakPoint = request.form.get(
        "weakPoint"
    )

    data = loadStudyData()

    if subject in data["subjects"]:

        data["subjects"][subject].setdefault(
            "weakPoints",
            []
        )

        if (
            weakPoint
            and weakPoint
            not in data["subjects"][subject]["weakPoints"]
        ):

            data["subjects"][subject][
                "weakPoints"
            ].append(
                weakPoint
            )

    saveStudyData(
        data
    )

    return redirect(
        url_for(
            "progress",
            subject=subject
        )
    )


# --------------------------------------------------
# REMOVE WEAK POINT
# --------------------------------------------------

@app.route(
    "/remove-weak-point",
    methods=["POST"]
)
def removeWeakPoint():

    subject = request.form.get(
        "subject"
    )

    weakPoint = request.form.get(
        "weakPoint"
    )

    data = loadStudyData()

    if subject in data["subjects"]:

        data["subjects"][subject].setdefault(
            "weakPoints",
            []
        )

        if (
            weakPoint
            in data["subjects"][subject]["weakPoints"]
        ):

            data["subjects"][subject][
                "weakPoints"
            ].remove(
                weakPoint
            )

    saveStudyData(
        data
    )

    return redirect(
        url_for(
            "progress",
            subject=subject
        )
    )


# --------------------------------------------------
# START APP
# --------------------------------------------------

if __name__ == "__main__":

    app.run(
        debug=True
    )
