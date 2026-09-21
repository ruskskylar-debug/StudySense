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
    model="Qwen/Qwen2.5-0.5B-Instruct",
    device_map="auto"
)

    print("StudySense AI is ready.")
    print("LLM =", llm)

    test = llm(
    "What is DNA?",
    max_new_tokens=50
)

    print(test)

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
    print("CREATE FLASHCARDS ROUTE HIT")

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

    cards = []

    sentences = re.split(r'[.!?]', text)

    for sentence in sentences:

        sentence = sentence.strip()

        if len(sentence) < 30:
            continue

        lowerSentence = sentence.lower()

        question = None
        answer = sentence

        if " is " in lowerSentence:

            term = sentence.split(" is ")[0].strip()

            question = f"What is {term}?"

        elif " are " in lowerSentence:

            parts = sentence.split(" are ", 1)

            if parts[0].strip().lower() == "there":
                question = f"What does the study material identify in this statement?"
            else:
                question = f"What are {parts[0].strip()}?"

        elif " helps " in lowerSentence:

            parts = sentence.split(" helps ", 1)

            question = f"How does {parts[0].strip()} help?"

        elif " allows " in lowerSentence:

            parts = sentence.split(" allows ", 1)

            question = f"What does {parts[0].strip()} allow?"

        elif " used for " in lowerSentence:

            parts = sentence.split(" used for ", 1)

            question = f"What is {parts[0].strip()} used for?"

        elif " important " in lowerSentence:

            question = f"Why is this concept important?"

        elif " produces " in lowerSentence:

            parts = sentence.split(" produces ")

            question = f"What does {parts[0].strip()} produce?"

        elif " contains " in lowerSentence:

            parts = sentence.split(" contains ")

            question = f"What does {parts[0].strip()} contain?"

        elif " creates " in lowerSentence:

            parts = sentence.split(" creates ")

            question = f"What does {parts[0].strip()} create?"

        elif " includes " in lowerSentence:

            parts = sentence.split(" includes ")

            question = f"What does {parts[0].strip()} include?"
        elif " means " in lowerSentence:

            parts = sentence.split(" means ", 1)

            question = f"What does {parts[0].strip()} mean?"

        elif " refers to " in lowerSentence:

            parts = sentence.split(" refers to ", 1)

            question = f"What does {parts[0].strip()} refer to?"

        elif " called " in lowerSentence:

            parts = sentence.split(" called ", 1)

            question = f"What is called {parts[1].strip()}?"

        elif " consists of " in lowerSentence:

            parts = sentence.split(" consists of ", 1)

            question = f"What does {parts[0].strip()} consist of?"

        if question:

            cards.append({
                "question": question,
                "answer": answer
            })

        if len(cards) >= number:
            break

    if not cards:

        cards.append({
            "question": "No flashcards could be created.",
            "answer": "There was not enough study material."
        })

    return cards


def generateAnswer(question, material):
    try:
        prompt = f"""
You are the StudySense AI Assistant.

Use the study material provided below to answer the student's question.


Study Material:
{material}

Student Question:
{question}

Instructions:
- Every question must be complete and understandable on its own.
- Do not use vague questions such as "What are there?", "What are they?", or "What is it?"
- Include the specific topic in the question.
- The question must make sense without seeing the study material.
- Answer only the student's specific question.
- Keep the answer concise and focused.
- Use 2 to 4 sentences unless more explanation is necessary.
- Do not include unrelated information from the study material.
- Explain the answer clearly in student-friendly language.
- Do not make up information that is not supported by the study material.
- If the answer cannot be found in the study material, say that the information was not found.


Answer:
"""

        result = llm(
            prompt,
            max_new_tokens=200,
            do_sample=False
        )

        answer = result[0]["generated_text"]

        if "Answer:" in answer:
            answer = answer.split("Answer:", 1)[1].strip()

        return answer

    except Exception as error:
        return "StudySense could not generate an answer.\n\n" + str(error)
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
