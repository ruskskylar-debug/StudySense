from flask import Flask, render_template, request, redirect, url_for, jsonify
import os
import json
import re
import random
import uuid
from datetime import datetime

from src.dataInput import readFile, cleanText


app = Flask(__name__)
app.secret_key = "studysense-secret-key"


APP_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_FILE = os.path.join(APP_DIR, "data", "studyData.json")


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

        data = json.load(file)

    # Make sure every subject has the fields used by the current
    # flashcard/progress system, including older studyData.json files.
    for subjectData in data.get("subjects", {}).values():
        subjectData.setdefault("flashcardSets", [])
        subjectData.setdefault("flashcardResults", [])
        subjectData.setdefault("weakPoints", [])

    return data


def saveStudyData(data):

    os.makedirs(
        os.path.dirname(DATA_FILE),
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



def getSubjectTopics(subjectData):

    topics = []
    seenTopics = set()

    for material in subjectData.get("materials", []):

        topic = material.get("topic", "").strip()

        if not topic:
            continue

        topicKey = topic.lower()

        if topicKey not in seenTopics:
            topics.append(topic)
            seenTopics.add(topicKey)

    return sorted(topics, key=str.lower)

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
            os.path.join(APP_DIR, "data", "raw"),
            exist_ok=True
        )

        fileName = uploadedFile.filename

        filePath = os.path.join(
            APP_DIR, "data", "raw",
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
            os.path.join(APP_DIR, "data", "cleaned"),
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
            APP_DIR, "data", "cleaned",
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
# DELETE STUDY MATERIAL
# --------------------------------------------------

@app.route("/delete-material", methods=["POST"])
def deleteMaterial():

    subject = request.form.get("subject", "")
    materialIndex = request.form.get("materialIndex", "")

    data = loadStudyData()

    if subject not in data["subjects"]:
        return redirect(url_for("home"))

    try:
        materialIndex = int(materialIndex)
    except (TypeError, ValueError):
        return redirect(url_for("home"))

    materials = data["subjects"][subject].get("materials", [])

    if materialIndex < 0 or materialIndex >= len(materials):
        return redirect(url_for("home"))

    material = materials[materialIndex]
    fileName = material.get("fileName", "")

    if fileName and fileName != "Text Input":
        rawFilePath = os.path.join(APP_DIR, "data", "raw", fileName)
        cleanedFileName = fileName.rsplit(".", 1)[0] + "_cleaned.txt" if "." in fileName else fileName + "_cleaned.txt"
        cleanedFilePath = os.path.join(APP_DIR, "data", "cleaned", cleanedFileName)

        if os.path.exists(rawFilePath):
            os.remove(rawFilePath)

        if os.path.exists(cleanedFilePath):
            os.remove(cleanedFilePath)

    materials.pop(materialIndex)

    saveStudyData(data)

    return redirect(url_for("home"))


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
        question,
        materialText
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


def rebuildWeakPoints(subjectData):

    weakPoints = []
    seenQuestions = set()

    for flashcardSet in subjectData.get("flashcardSets", []):

        if flashcardSet.get("choice") == "weak":
            continue

        for card in flashcardSet.get("cards", []):

            if card.get("result") not in ["almost", "needHelp"]:
                continue

            question = card.get("question", "").strip()

            if question and question not in seenQuestions:
                weakPoints.append(question)
                seenQuestions.add(question)

    subjectData["weakPoints"] = weakPoints
    return weakPoints


def getWeakFlashcards(subjectData):

    weakCards = []
    seenQuestions = set()

    flashcardSets = subjectData.get(
        "flashcardSets",
        []
    )

    for flashcardSet in reversed(flashcardSets):

        if flashcardSet.get("choice") == "weak":
            continue

        for cardIndex, card in enumerate(
            flashcardSet.get("cards", [])
        ):

            if card.get("result") not in ["almost", "needHelp"]:
                continue

            question = card.get("question", "").strip()

            if not question or question in seenQuestions:
                continue

            weakCards.append({
                "question": question,
                "answer": card.get("answer", ""),
                "result": None,
                "sourceSetId": flashcardSet.get("id"),
                "sourceCardIndex": cardIndex
            })

            seenQuestions.add(question)

    return weakCards


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

    setId = request.args.get(
        "set_id",
        ""
    )

    materials = []
    topics = []
    weakPoints = []
    cards = None
    activeSet = None

    if selectedSubject in data["subjects"]:

        subjectData = data["subjects"][
            selectedSubject
        ]

        materials = subjectData.get(
            "materials",
            []
        )

        topics = getSubjectTopics(subjectData)

        weakPoints = subjectData.get(
            "weakPoints",
            []
        )

        for flashcardSet in subjectData.get(
            "flashcardSets",
            []
        ):

            if flashcardSet.get("id") == setId:

                activeSet = flashcardSet
                cards = flashcardSet.get(
                    "cards",
                    []
                )
                break

    return render_template(
        "flashcards.html",
        subjects=data["subjects"],
        materials=materials,
        topics=topics,
        weakPoints=weakPoints,
        selectedSubject=selectedSubject,
        cards=cards,
        activeSet=activeSet
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
        "topic",
        ""
    ).strip()

    data = loadStudyData()

    if subject not in data["subjects"]:

        return render_template(
            "flashcards.html",
            subjects=data["subjects"],
            materials=[],
            topics=[],
            weakPoints=[],
            selectedSubject="",
            cards=None,
            activeSet=None,
            error="Please choose a subject first."
        )

    subjectData = data["subjects"][
        subject
    ]

    topics = getSubjectTopics(subjectData)

    subjectData.setdefault(
        "materials",
        []
    )

    subjectData.setdefault(
        "weakPoints",
        []
    )

    subjectData.setdefault(
        "flashcardSets",
        []
    )

    # Weak Points uses every card currently marked Almost or Need help.
    # The user does not choose a number for this set.
    if choice == "weak":

        # Resume an unfinished weak-point review instead of creating
        # another copy of the same review set.
        for existingSet in reversed(subjectData.get("flashcardSets", [])):
            if (
                existingSet.get("choice") == "weak"
                and existingSet.get("cards")
                and not all(
                    card.get("result") is not None
                    for card in existingSet.get("cards", [])
                )
            ):
                return redirect(
                    url_for(
                        "flashcards",
                        subject=subject,
                        set_id=existingSet.get("id")
                    )
                )

        cards = getWeakFlashcards(
            subjectData
        )

        if not cards:

            return render_template(
                "flashcards.html",
                subjects=data["subjects"],
                materials=subjectData["materials"],
                topics=topics,
                weakPoints=subjectData["weakPoints"],
                selectedSubject=subject,
                cards=None,
                activeSet=None,
                error=(
                    "There are no weak-point flashcards yet. "
                    "Mark cards as Almost or Need help first."
                )
            )

        title = "Weak Points Review"

    else:

        number = request.form.get(
            "number",
            "10"
        )

        try:
            number = max(
                1,
                min(int(number), 20)
            )
        except (TypeError, ValueError):
            number = 10

        materialText = ""

        if choice == "all":

            for material in subjectData["materials"]:

                materialText += (
                    material["text"]
                    + "\n\n"
                )

            title = "All Material Review"

        elif choice == "topic":

            if not topic:

                return render_template(
                    "flashcards.html",
                    subjects=data["subjects"],
                    materials=subjectData["materials"],
                    topics=topics,
                    weakPoints=subjectData["weakPoints"],
                    selectedSubject=subject,
                    cards=None,
                    activeSet=None,
                    error="Please choose a topic."
                )

            for material in subjectData["materials"]:

                if material.get("topic", "").strip().casefold() == topic.strip().casefold():

                    materialText += (
                        material["text"]
                        + "\n\n"
                    )

            title = f"{topic} Review"

        else:

            return render_template(
                "flashcards.html",
                subjects=data["subjects"],
                materials=subjectData["materials"],
                topics=topics,
                weakPoints=subjectData["weakPoints"],
                selectedSubject=subject,
                cards=None,
                activeSet=None,
                error="Please choose what you want to study."
            )

        if materialText.strip() == "":

            return render_template(
                "flashcards.html",
                subjects=data["subjects"],
                materials=subjectData["materials"],
                topics=topics,
                weakPoints=subjectData["weakPoints"],
                selectedSubject=subject,
                cards=None,
                activeSet=None,
                error="There is not enough study material for this subject yet."
            )

        cards = generateFlashcards(
            materialText,
            number
        )

        if not cards:

            return render_template(
                "flashcards.html",
                subjects=data["subjects"],
                materials=subjectData["materials"],
                topics=topics,
                weakPoints=subjectData["weakPoints"],
                selectedSubject=subject,
                cards=None,
                activeSet=None,
                error="There was not enough information to create flashcards."
            )

    setId = uuid.uuid4().hex[:12]

    for card in cards:
        card.setdefault("result", None)

    flashcardSet = {
        "id": setId,
        "title": title,
        "choice": choice,
        "topic": topic,
        "createdAt": datetime.now().strftime(
            "%Y-%m-%d %H:%M:%S"
        ),
        "cards": cards
    }

    subjectData["flashcardSets"].append(
        flashcardSet
    )

    saveStudyData(data)

    if request.headers.get("X-Requested-With") == "fetch":
        return jsonify({"success": True})

    return redirect(
        url_for(
            "flashcards",
            subject=subject,
            set_id=setId
        )
    )


def cleanFlashcardText(text):

    text = text.replace("\r", "\n")

    lines = [
        line.strip()
        for line in text.split("\n")
    ]

    blocks = []
    current = ""
    isBullet = False

    for line in lines:

        if not line:
            if current:
                blocks.append(current.strip())
                current = ""
                isBullet = False
            continue

        bulletMatch = re.match(
            r"^[•●▪◦]\s*(.*)$",
            line
        )

        if bulletMatch:

            if current:
                blocks.append(current.strip())

            current = bulletMatch.group(1).strip()
            isBullet = True

        elif isBullet:

            current += " " + line

        else:

            if current:
                blocks.append(current.strip())

            current = line

    if current:
        blocks.append(current.strip())

    cleanedBlocks = []

    for block in blocks:

        block = re.sub(
            r"\s+",
            " ",
            block
        ).strip()

        # Remove short slide headings such as:
        # Memory
        # Sensory Memory
        # The Three Basic Processes
        # Long-Term Memory
        #
        # The actual information is contained in the
        # bullet points underneath them.
        if (
            not re.search(r"[.!?]$", block)
            and len(block.split()) <= 10
        ):
            continue

        # Turn slide-style definitions such as:
        # Encoding: transforming information...
        #
        # into:
        # Encoding is transforming information...
        definitionMatch = re.match(
            r"^([A-Za-z][A-Za-z0-9 /&()\-\']{0,80}):\s+(.+)$",
            block
        )

        if definitionMatch:
            block = (
                definitionMatch.group(1)
                + " is "
                + definitionMatch.group(2)
            )

        if not re.search(r"[.!?]$", block):
            block += "."

        cleanedBlocks.append(block)

    return " ".join(cleanedBlocks)


    
def addFlashcard(cards, question, answer, seenQuestions, number):
    question = re.sub(r"\s+", " ", question).strip()
    answer = re.sub(r"\s+", " ", answer).strip()

    if not question or not answer:
        return

    question = question[0].upper() + question[1:]

    if not question.endswith("?"):
        question += "?"

    if question.lower() in seenQuestions:
        return

    if len(question.split()) < 4:
        return

    cards.append({
        "question": question,
        "answer": answer,
        "result": None
    })

    seenQuestions.add(question.lower())


def generateFlashcards(text, number):

    text = cleanFlashcardText(text)
    cards = []
    seenQuestions = set()

    # Remove the common biology title if it was joined to the first sentence.
    text = re.sub(
        r"^.*?\bCells are\b",
        "Cells are",
        text,
        count=1,
        flags=re.IGNORECASE
    )

    sentences = re.split(r"(?<=[.!?])\s+", text)

    # Shuffle eligible material so creating another set can produce
    # different questions when there is enough material to choose from.
    random.shuffle(sentences)

    def cleanSubject(subject):
        subject = re.sub(r"\s+", " ", subject.strip())

        if not subject:
            return subject

        firstWord = subject.split(" ", 1)[0]

        if firstWord.lower() in ["a", "an", "the"]:
            return firstWord.lower() + (
                subject[len(firstWord):]
                if len(subject) > len(firstWord)
                else ""
            )

        # Keep acronyms such as DNA uppercase.
        if firstWord.isupper() and len(firstWord) <= 5:
            return subject

        return firstWord.lower() + (
            subject[len(firstWord):]
            if len(subject) > len(firstWord)
            else ""
        )

    for sentence in sentences:
        sentence = sentence.strip()

        if len(sentence) < 25:
            continue

        lower = sentence.lower()
        question = None

        # Skip headings and pronoun-only openings.
        if lower.startswith(("their ", "these ", "this ", "it ", "they ")):
            continue

        # HIGH-QUALITY PATTERNS FIRST

        if re.match(r"^Every living organism is made of\s+", sentence, re.I):
            question = "What are all living organisms made of"

        elif re.match(r"^(.+?)\s+do not have\s+", sentence, re.I):
            m = re.match(r"^(.+?)\s+do not have\s+", sentence, re.I)
            subject = cleanSubject(m.group(1))
            question = f"What do {subject} not have"

        elif re.match(r"^(.+?)\s+is composed of\s+", sentence, re.I):
            m = re.match(r"^(.+?)\s+is composed of\s+", sentence, re.I)
            subject = cleanSubject(m.group(1))
            question = f"What is {subject} composed of"

        elif re.match(r"^(.+?)\s+consists of\s+", sentence, re.I):
            m = re.match(r"^(.+?)\s+consists of\s+", sentence, re.I)
            subject = cleanSubject(m.group(1))
            question = f"What does {subject} consist of"

        elif re.match(r"^(.+?)\s+are connected processes\.?$", sentence, re.I):
            m = re.match(r"^(.+?)\s+are connected processes\.?$", sentence, re.I)
            subject = cleanSubject(m.group(1))
            question = f"What are {subject}"

        elif re.match(
            r"^Mitosis and meiosis have different purposes\.?$",
            sentence,
            re.I
        ):
            question = "What is different about the purposes of mitosis and meiosis"

        elif re.match(r"^(.+?)\s+is\s+", sentence, re.I):
            m = re.match(r"^(.+?)\s+is\s+", sentence, re.I)
            subject = cleanSubject(m.group(1))

            if len(subject.split()) <= 8:
                question = f"What is {subject}"

        elif re.match(r"^(.+?)\s+are\s+", sentence, re.I):
            m = re.match(r"^(.+?)\s+are\s+", sentence, re.I)
            subject = cleanSubject(m.group(1))

            if len(subject.split()) <= 8:
                question = f"What are {subject}"

        elif re.match(r"^(.+?)\s+has\s+", sentence, re.I):
            m = re.match(r"^(.+?)\s+has\s+", sentence, re.I)
            subject = cleanSubject(m.group(1))

            if len(subject.split()) <= 8:
                question = f"What does {subject} have"

        elif re.match(r"^(.+?)\s+have\s+", sentence, re.I):
            m = re.match(r"^(.+?)\s+have\s+", sentence, re.I)
            subject = cleanSubject(m.group(1))

            if len(subject.split()) <= 8:
                question = f"What do {subject} have"

        elif re.match(r"^(.+?)\s+contains\s+", sentence, re.I):
            m = re.match(r"^(.+?)\s+contains\s+", sentence, re.I)
            subject = cleanSubject(m.group(1))

            if len(subject.split()) <= 8:
                question = f"What does {subject} contain"

        elif re.match(r"^(.+?)\s+produces\s+", sentence, re.I):
            m = re.match(r"^(.+?)\s+produces\s+", sentence, re.I)
            subject = cleanSubject(m.group(1))

            if len(subject.split()) <= 8:
                question = f"What does {subject} produce"

        elif re.match(r"^(.+?)\s+produce\s+", sentence, re.I):
            m = re.match(r"^(.+?)\s+produce\s+", sentence, re.I)
            subject = cleanSubject(m.group(1))

            if len(subject.split()) <= 8:
                question = f"What do {subject} produce"

        if question:
            addFlashcard(
                cards,
                question,
                sentence,
                seenQuestions,
                number
            )

        if len(cards) >= number:
            break

    return cards

# --------------------------------------------------
# AI ANSWERS
# --------------------------------------------------


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
- Answer only the question that was asked.
- Keep the answer short and focused.
- Use 1 to 3 sentences.
- Do not add unrelated information.
- Do not make up information that is not supported by the study material.

Answer:
"""

        result = llm(
            prompt,
            max_new_tokens=100,
            do_sample=False
        )

        answer = result[0]["generated_text"]

        if "Answer:" in answer:
            answer = answer.split(
                "Answer:",
                1
            )[1].strip()

        sentences = re.split(
            r"(?<=[.!?])\s+",
            answer
        )

        if (
            len(sentences) > 1
            and not re.search(r"[.!?]$", sentences[-1])
        ):
            sentences = sentences[:-1]

        answer = " ".join(
            sentences
        ).strip()

        # Qwen sometimes gives a useful answer and then adds the fallback
        # message even when the information was found. Remove that extra
        # message when an actual answer came before it.
        fallback = "I cannot find that information in the study material."

        if fallback in answer:
            answerBeforeFallback = answer.split(
                fallback,
                1
            )[0].strip()

            if answerBeforeFallback:
                answer = answerBeforeFallback
            else:
                answer = fallback

        return answer

    except Exception as error:
        return (
            "StudySense could not generate an answer.\n\n"
            + str(error)
        )


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

    setId = request.form.get(
        "setId"
    )

    cardIndex = request.form.get(
        "cardIndex"
    )

    result = request.form.get(
        "result"
    )

    if result not in [
        "gotIt",
        "almost",
        "needHelp"
    ]:
        return jsonify({"success": False})

    data = loadStudyData()

    if subject not in data["subjects"]:
        return jsonify({"success": False})

    subjectData = data["subjects"][subject]
    subjectData.setdefault("flashcardSets", [])
    flashcardSets = subjectData["flashcardSets"]

    targetSet = None

    for flashcardSet in flashcardSets:
        if flashcardSet.get("id") == setId:
            targetSet = flashcardSet
            break

    if targetSet is None:
        return jsonify({"success": False})

    try:
        cardIndex = int(cardIndex)
    except (TypeError, ValueError):
        return jsonify({"success": False})

    cards = targetSet.get("cards", [])

    if cardIndex < 0 or cardIndex >= len(cards):
        return jsonify({"success": False})

    cards[cardIndex]["result"] = result

    # Weak-point cards remember which original card they came from.
    # Do not change the original saved set until the entire Weak Points
    # review is finished. This keeps the previous set's counts accurate
    # while the review is still in progress.
    selectedCard = cards[cardIndex]

    sourceSetId = selectedCard.get("sourceSetId")
    sourceCardIndex = selectedCard.get("sourceCardIndex")

    reviewComplete = True

    if targetSet.get("choice") == "weak":
        reviewComplete = all(
            card.get("result") is not None
            for card in cards
        )

    if sourceSetId and reviewComplete:
        for sourceSet in flashcardSets:
            if sourceSet.get("id") != sourceSetId:
                continue

            sourceCards = sourceSet.get("cards", [])

            if (
                isinstance(sourceCardIndex, int)
                and 0 <= sourceCardIndex < len(sourceCards)
            ):
                sourceCards[sourceCardIndex]["result"] = result

    # Keep saved weak-point copies synchronized with their source card
    # only after the whole weak-point review is complete.
    if sourceSetId and reviewComplete:
        for flashcardSet in flashcardSets:
            for card in flashcardSet.get("cards", []):
                if (
                    card.get("sourceSetId") == sourceSetId
                    and card.get("sourceCardIndex") == sourceCardIndex
                ):
                    card["result"] = result

    # Normal flashcard results update Weak Points immediately.
    # A Weak Points review updates them only after all of its cards
    # have been answered.
    if targetSet.get("choice") == "weak":
        if reviewComplete:
            rebuildWeakPoints(subjectData)
    else:
        rebuildWeakPoints(subjectData)

    # Keep the older results list updated for compatibility with
    # existing saved data.
    subjectData.setdefault(
        "flashcardResults",
        []
    )

    question = cards[cardIndex].get(
        "question",
        ""
    )

    existingResult = None

    for savedResult in subjectData["flashcardResults"]:
        if savedResult.get("question") == question:
            existingResult = savedResult
            break

    if existingResult:
        existingResult["result"] = result
    else:
        subjectData["flashcardResults"].append({
            "question": question,
            "result": result
        })

    saveStudyData(data)

    return redirect(
        url_for(
            "flashcards",
            subject=subject,
            set_id=setId
        )
    )


# --------------------------------------------------
# DELETE FLASHCARD SET
# --------------------------------------------------

@app.route("/delete-flashcard-set", methods=["POST"])
def deleteFlashcardSet():

    subject = request.form.get("subject", "")
    setId = request.form.get("setId", "")

    data = loadStudyData()

    if subject not in data["subjects"]:
        return redirect(url_for("progress", subject=subject))

    subjectData = data["subjects"][subject]
    flashcardSets = subjectData.get("flashcardSets", [])

    subjectData["flashcardSets"] = [
        flashcardSet
        for flashcardSet in flashcardSets
        if flashcardSet.get("id") != setId
    ]

    rebuildWeakPoints(subjectData)
    saveStudyData(data)

    return redirect(url_for("progress", subject=subject))


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
    flashcardSets = []

    if selectedSubject in data["subjects"]:

        subjectData = data["subjects"][
            selectedSubject
        ]

        materials = subjectData.get(
            "materials",
            []
        )

        weakPoints = []

        flashcardResults = subjectData.get(
            "flashcardResults",
            []
        )

        flashcardSets = [
            flashcardSet
            for flashcardSet in subjectData.get("flashcardSets", [])
            if flashcardSet.get("choice") != "weak"
        ]

    # Weak Points are stored as a stable list while a review is in progress.
    # They are rebuilt after normal result changes or after a complete weak-point review.
    weakPoints = subjectData.get("weakPoints", []) if selectedSubject in data["subjects"] else []

    # Add a simple summary to every saved set for display.
    for flashcardSet in flashcardSets:

        cards = flashcardSet.get(
            "cards",
            []
        )

        flashcardSet["gotItCount"] = sum(
            1 for card in cards
            if card.get("result") == "gotIt"
        )

        flashcardSet["almostCount"] = sum(
            1 for card in cards
            if card.get("result") == "almost"
        )

        flashcardSet["needHelpCount"] = sum(
            1 for card in cards
            if card.get("result") == "needHelp"
        )

    totalResults = 0
    gotItCount = 0

    for flashcardSet in flashcardSets:

        for card in flashcardSet.get("cards", []):

            if card.get("result"):

                totalResults += 1

                if card.get("result") == "gotIt":
                    gotItCount += 1

                elif card.get("result") == "almost":
                    gotItCount += 0.5

    progressPercent = 0

    if totalResults > 0:
        progressPercent = round(
            (gotItCount / totalResults) * 100
        )

    savedResults = []

    for flashcardSet in flashcardSets:
        for card in flashcardSet.get("cards", []):
            if card.get("result"):
                savedResults.append({
                    "question": card.get("question", ""),
                    "result": card.get("result")
                })

    return render_template(
        "progress.html",
        subjects=data["subjects"],
        materials=materials,
        weakPoints=weakPoints,
        selectedSubject=selectedSubject,
        progressPercent=progressPercent,
        flashcardResults=savedResults,
        flashcardSets=flashcardSets
    )


# --------------------------------------------------
# START APP
# --------------------------------------------------

if __name__ == "__main__":

    app.run(
        debug=True
    )
