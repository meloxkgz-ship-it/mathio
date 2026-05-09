#!/usr/bin/env python3
"""Sync Localizable.xcstrings with every UI-facing string literal in
the Mathio Swift sources. For each missing key:

* If the string is math-only (no German-distinct word), we inject a DE
  entry with the **same** value — the App Store compiler treats this as
  legitimately translated (Apple does this themselves for numerals).
* If it's prose, we look it up in the manual translation table below
  and inject the German rendering.

Run from `iOS/Mathio/Mathio/`.
"""
from __future__ import annotations
import json
import os
import re
import sys


# Manual prose translations. Anything not listed here AND not math-only
# triggers a hard fail so we never silently leave English in the bundle.
PROSE: dict[str, str] = {
    # Curriculum: lesson titles
    "Power rule": "Potenzregel",
    "Sum rule": "Summenregel",
    "Constant rule": "Konstantenregel",
    "Chain rule": "Kettenregel",
    "Constant multiple": "Konstanter Faktor",
    "Power rule (integral)": "Potenzregel (Integral)",
    "Quadratic formula": "Quadratische Lösungsformel",
    "Discriminant": "Diskriminante",
    "Difference of squares": "Differenz zweier Quadrate",
    "Perfect square": "Quadratische Ergänzung",
    "Common factor": "Gemeinsamer Faktor",
    "Common denominator": "Gemeinsamer Nenner",
    "Increase / decrease": "Erhöhen / Verringern",
    "Percent of": "Prozent von",
    "Order": "Reihenfolge",
    "Two-step rule": "Zweistufige Regel",
    "Inverse operations": "Umkehroperationen",
    "Sign rules": "Vorzeichenregeln",
    "Subtracting a negative": "Eine negative Zahl abziehen",
    "Direct substitution": "Direktes Einsetzen",
    "Famous limit": "Berühmter Grenzwert",
    "Theorem": "Lehrsatz",
    "Pythagorean": "Pythagoras",
    "Coordinates": "Koordinaten",
    "Heron's formula": "Heronsche Formel",
    "Standard": "Standard",
    "Trig basics": "Trigonometrie-Grundlagen",
    "Sine": "Sinus",
    "Cosine": "Kosinus",
    "Tangent": "Tangens",
    "Tangent identity": "Tangens-Identität",
    "Special values": "Besondere Werte",
    "Even / odd": "Gerade / ungerade",
    "Slope-intercept form": "Steigungs-Achsenabschnitts-Form",
    "Slope from two points": "Steigung aus zwei Punkten",
    "Definition of zero exponent.": "Definition des Exponenten 0.",
    "Negative": "Negativer Exponent",
    "Power": "Potenz",
    "Quotient": "Quotient",
    "Product": "Produkt",
    "Simplify": "Vereinfachen",
    "Negative exponent → reciprocal.": "Negativer Exponent → Kehrwert.",
    "A negative exponent flips the base.": "Ein negativer Exponent kehrt die Basis um.",
    "Same base → add the exponents.": "Gleiche Basis → Exponenten addieren.",
    "Same base → subtract the exponents.": "Gleiche Basis → Exponenten subtrahieren.",
    "Multiply exponents.": "Exponenten multiplizieren.",
    "Subtract exponents.": "Exponenten subtrahieren.",
    "Add exponents.": "Exponenten addieren.",
    "By convention, any nonzero base to the 0 is 1.":
        "Per Konvention: jede Basis ≠ 0 hoch 0 ergibt 1.",

    # Question prompts
    "Compute 1/2 + 1/3. Give the simplest fraction.":
        "Berechne 1/2 + 1/3. Als einfachster Bruch.",
    "Simplify 8/12.": "Kürze 8/12.",
    "Which is larger?": "Was ist größer?",
    "Compute 2/3 − 1/6.": "Berechne 2/3 − 1/6.",
    "True or false: 2/4 + 1/2 = 1.": "Wahr oder falsch: 2/4 + 1/2 = 1.",
    "What is 20% of 80?": "Was sind 20 % von 80?",
    "A jacket costs $80 and is 25% off. What's the sale price?":
        "Eine Jacke kostet 80 $ mit 25 % Rabatt. Was ist der reduzierte Preis?",
    "If a price goes up by 10%, then down by 10%, the result is:":
        "Ein Preis steigt um 10 % und fällt dann um 10 %. Resultat:",
    "15 is what percent of 60?": "Wieviel Prozent von 60 sind 15?",
    "True or false: 200% of 5 equals 10.": "Wahr oder falsch: 200 % von 5 ergibt 10.",
    "Compute (3 + 4) · 2.": "Berechne (3 + 4) · 2.",
    "Compute 3 + 4 · 2.": "Berechne 3 + 4 · 2.",
    "Compute 12 ÷ 4 + 2.": "Berechne 12 ÷ 4 + 2.",
    "Which equals 17?": "Was ergibt 17?",
    "Compute 2³ − 2 · 3.": "Berechne 2³ − 2 · 3.",
    "Compute −7 + 3.": "Berechne −7 + 3.",
    "Compute 3 − (−2).": "Berechne 3 − (−2).",
    "Compute (−4)·(−5).": "Berechne (−4)·(−5).",
    "True or false: |−7| = 7.": "Wahr oder falsch: |−7| = 7.",
    "Which is largest?": "Welche Zahl ist am größten?",
    "Solve for x:": "Löse nach x:",
    "Solve: 7 = x + 4.": "Löse: 7 = x + 4.",
    "Which value of x satisfies 3(x − 2) = 9?": "Welcher x-Wert erfüllt 3(x − 2) = 9?",
    "Solve: −2x + 8 = 0.": "Löse: −2x + 8 = 0.",
    "Solve x² − 9 = 0. Smallest first, comma-separated.":
        "Löse x² − 9 = 0. Kleinster Wert zuerst, kommagetrennt.",
    "Solve x² − 5x + 6 = 0. Give both roots, comma-separated, smallest first.":
        "Löse x² − 5x + 6 = 0. Beide Lösungen, kommagetrennt, kleinster Wert zuerst.",
    "Solve: x² + x − 6 = 0. Smallest first.":
        "Löse: x² + x − 6 = 0. Kleinster Wert zuerst.",
    "How many real solutions does x² + 4x + 5 = 0 have?":
        "Wie viele reelle Lösungen hat x² + 4x + 5 = 0?",
    "What's the discriminant of 2x² + 3x − 5?":
        "Wie lautet die Diskriminante von 2x² + 3x − 5?",
    "Simplify 2³ · 2⁴.": "Vereinfache 2³ · 2⁴.",
    "Simplify (3²)³.": "Vereinfache (3²)³.",
    "What is 5⁻²?": "Was ist 5⁻²?",
    "Simplify x⁵ / x².": "Vereinfache x⁵ / x².",
    "True or false: a⁰ = 1 for any nonzero a.":
        "Wahr oder falsch: a⁰ = 1 für jedes a ≠ 0.",
    "Find lim x→2 (3x + 1).": "Finde lim x→2 (3x + 1).",
    "Find lim x→0 (x² + 5).": "Finde lim x→0 (x² + 5).",
    "Find lim x→∞ 1/x.": "Finde lim x→∞ 1/x.",
    "What does 1/x do as x grows?": "Was macht 1/x, wenn x wächst?",
    "What is lim x→0 sin(x)/x?": "Was ist lim x→0 sin(x)/x?",
    "True or false: lim x→3 (x² − 9)/(x − 3) = 6.":
        "Wahr oder falsch: lim x→3 (x² − 9)/(x − 3) = 6.",
    "Find the derivative of 3x² + 2x − 7.":
        "Bestimme die Ableitung von 3x² + 2x − 7.",
    "Which is the derivative of 5x⁴?": "Welche ist die Ableitung von 5x⁴?",
    "What is the slope of f(x) = x³ at x = 2?":
        "Wie groß ist die Steigung von f(x) = x³ an der Stelle x = 2?",
    "True or false: d/dx √x = 1/(2√x).": "Wahr oder falsch: d/dx √x = 1/(2√x).",
    "True or false: d/dx (sin x) = cos x.": "Wahr oder falsch: d/dx (sin x) = cos x.",
    "Compute ∫ x³ dx.": "Berechne ∫ x³ dx.",
    "Compute ∫ 5 dx.": "Berechne ∫ 5 dx.",
    "Find ∫ cos x dx.": "Finde ∫ cos x dx.",
    "Compute ∫ 2x dx. Use C for the constant.":
        "Berechne ∫ 2x dx. Nutze C für die Konstante.",
    "Evaluate ∫ (−1) dx.": "Berechne ∫ (−1) dx.",
    "A right triangle has legs 3 and 4. Find the hypotenuse.":
        "Ein rechtwinkliges Dreieck hat die Katheten 3 und 4. Bestimme die Hypotenuse.",
    "Legs 6 and 8. Hypotenuse?": "Katheten 6 und 8. Hypotenuse?",
    "Hypotenuse is 13, one leg is 5. The other leg is:":
        "Hypotenuse 13, eine Kathete ist 5. Die andere Kathete:",
    "Is 5-12-13 a right triangle?": "Ist 5-12-13 ein rechtwinkliges Dreieck?",
    "Diagonal of a square with side 1?": "Diagonale eines Quadrats mit Seite 1?",
    "Area of a circle with radius 3? In terms of π.":
        "Flächeninhalt eines Kreises mit Radius 3? In Einheiten von π.",
    "Circumference of a circle with radius 5? In terms of π.":
        "Umfang eines Kreises mit Radius 5? In Einheiten von π.",
    "If the diameter is 8, the radius is:": "Wenn der Durchmesser 8 ist, ist der Radius:",
    "Doubling the radius makes the area:":
        "Wird der Radius verdoppelt, wird der Flächeninhalt:",
    "True or false: π is approximately 3.14.":
        "Wahr oder falsch: π ist ungefähr 3,14.",
    "Triangle with base 10 and height 6. Area?":
        "Dreieck mit Grundseite 10 und Höhe 6. Flächeninhalt?",
    "Right triangle with legs 5 and 12. Area?":
        "Rechtwinkliges Dreieck mit Katheten 5 und 12. Flächeninhalt?",
    "Equilateral triangle with side 2. Area?":
        "Gleichseitiges Dreieck mit Seite 2. Flächeninhalt?",
    "If base doubles and height stays the same, area:":
        "Verdoppelt sich die Grundseite und die Höhe bleibt, dann ist der Flächeninhalt:",
    "True or false: any two triangles with the same base and height have the same area.":
        "Wahr oder falsch: zwei Dreiecke mit gleicher Grundseite und Höhe haben den gleichen Flächeninhalt.",
    "Right triangle: opposite 3, hypotenuse 5. sin θ?":
        "Rechtwinkliges Dreieck: Gegenkathete 3, Hypotenuse 5. sin θ?",
    "What is sin 30°?": "Was ist sin 30°?",
    "What is cos 0°?": "Was ist cos 0°?",
    "What is tan 45°?": "Was ist tan 45°?",
    "True or false: sin 45° = cos 45°.": "Wahr oder falsch: sin 45° = cos 45°.",
    "If sin θ = 3/5 and θ is in Q1, what is cos θ?":
        "Wenn sin θ = 3/5 und θ in Q1, was ist cos θ?",
    "What is sin 180°?": "Was ist sin 180°?",
    "What is cos 90°?": "Was ist cos 90°?",
    "What is tan 90°?": "Was ist tan 90°?",
    "Which angle has sine equal to 1?": "Welcher Winkel hat den Sinus 1?",
    "True or false: cos(360°) = cos(0°).": "Wahr oder falsch: cos(360°) = cos(0°).",
    "Compute the discriminant.": "Berechne die Diskriminante.",
    "Factor.": "Faktorisiere.",
    "Factor: x² + 6x + 9.": "Faktorisiere: x² + 6x + 9.",
    "Factor: x² − 9.": "Faktorisiere: x² − 9.",
    "Factor: 6x + 9.": "Faktorisiere: 6x + 9.",
    "True or false: 4x² − 25 = (2x − 5)(2x + 5).":
        "Wahr oder falsch: 4x² − 25 = (2x − 5)(2x + 5).",
    "Which is a factor of x² + 5x + 6?": "Welches ist ein Faktor von x² + 5x + 6?",
    "Slope through (1, 2) and (3, 8).": "Steigung durch (1, 2) und (3, 8).",
    "Y-intercept of y = 2x − 5?": "y-Achsenabschnitt von y = 2x − 5?",
    "Slope of a horizontal line is:": "Die Steigung einer waagerechten Geraden ist:",
    "Through (0, 1) with slope 4. What's the y-value at x = 2?":
        "Durch (0, 1) mit Steigung 4. Wie groß ist y bei x = 2?",
    "True or false: y = 3 is a horizontal line.":
        "Wahr oder falsch: y = 3 ist eine waagerechte Gerade.",
    "Differentiate (x² + 1)³.": "Leite (x² + 1)³ ab.",
    "Differentiate sin(2x).": "Leite sin(2x) ab.",
    "Differentiate (3x + 2)⁴.": "Leite (3x + 2)⁴ ab.",
    "Differentiate (2x + 1)³. Use the chain rule.":
        "Leite (2x + 1)³ mit der Kettenregel ab.",
    "Differentiate e^(3x).": "Leite e^(3x) ab.",
    "Volume of a cube with side 4?": "Volumen eines Würfels mit Seite 4?",
    "Volume of a sphere with radius 3? In terms of π.":
        "Volumen einer Kugel mit Radius 3? In Einheiten von π.",
    "Volume of a cylinder with radius 2 and height 5? In terms of π.":
        "Volumen eines Zylinders mit Radius 2 und Höhe 5? In Einheiten von π.",
    "Doubling the radius of a sphere multiplies the volume by:":
        "Verdoppelt man den Radius einer Kugel, vervielfacht sich das Volumen mit:",
    "True or false: a 1×1×1 cube has volume 1.":
        "Wahr oder falsch: ein 1×1×1-Würfel hat das Volumen 1.",
    "What does tan θ · cos θ simplify to?": "Wozu vereinfacht sich tan θ · cos θ?",
    "Simplify sin(−x) + sin(x).": "Vereinfache sin(−x) + sin(x).",
    "True or false: cos(−π) = cos(π).": "Wahr oder falsch: cos(−π) = cos(π).",
    "If cos θ = 0, sin θ equals?": "Wenn cos θ = 0 ist, dann ist sin θ:",
    "True or false: sin²θ + cos²θ = 1 for every angle θ.":
        "Wahr oder falsch: sin²θ + cos²θ = 1 für jeden Winkel θ.",

    # Hints
    "Common denominator is 6.": "Gemeinsamer Nenner ist 6.",
    "Both share a factor of 4.": "Beide haben den Faktor 4 gemeinsam.",
    "Convert to a common denominator.": "Bring auf einen gemeinsamen Nenner.",
    "Use 6 as the denominator.": "Nutze 6 als Nenner.",
    "Simplify 2/4 first.": "Vereinfache zuerst 2/4.",
    "Convert to a fraction, then multiply.": "In Bruch umrechnen, dann multiplizieren.",
    "Multiply by 0.75.": "Mit 0,75 multiplizieren.",
    "Apply 1.10 then 0.90.": "Erst · 1,10, dann · 0,90.",
    "15/60.": "15/60.",
    "Parentheses first.": "Klammern zuerst.",
    "Multiply before adding.": "Erst multiplizieren, dann addieren.",
    "Division before addition.": "Erst dividieren, dann addieren.",
    "Multiplication before addition.": "Erst multiplizieren, dann addieren.",
    "Exponent, then multiplication, then subtraction.":
        "Erst Potenz, dann Multiplikation, dann Subtraktion.",
    "Think of a number line.": "Denk an die Zahlengerade.",
    "Subtracting a negative is adding.":
        "Eine negative Zahl abzuziehen ist dasselbe wie addieren.",
    "Two negatives → positive.": "Zwei Minuszeichen → Plus.",
    "Distance from zero is 7.": "Der Abstand zur Null ist 7.",
    "Closer to zero = larger when negative.":
        "Näher an der Null = größer (bei negativen Zahlen).",
    "Whatever you do to one side, do to the other.":
        "Was du auf einer Seite tust, tust du auch auf der anderen.",
    "Undo addition first, then division.": "Erst Addition rückgängig, dann dividieren.",
    "Distribute first: 3x − 6 = 9.": "Erst ausmultiplizieren: 3x − 6 = 9.",
    "Move 8 over, then divide.": "8 auf die andere Seite, dann teilen.",
    "Move all x to one side first.": "Erst alle x auf eine Seite bringen.",
    "Look for two numbers that multiply to 6 and add to −5.":
        "Suche zwei Zahlen, die multipliziert 6 und addiert −5 ergeben.",
    "Δ = b² − 4ac.": "Δ = b² − 4ac.",
    "Find roots: numbers that multiply to 6, add to 5.":
        "Suche zwei Zahlen, die multipliziert 6 und addiert 5 ergeben.",
    "Multiply both by 2: 3-4-5 triple.": "Beide mal 2: 3-4-5-Tripel.",
    "Square the legs, add, take the root.": "Katheten quadrieren, addieren, Wurzel ziehen.",
    "Check 5² + 12² = 13².": "Prüfe 5² + 12² = 13².",
    "Half of the diameter.": "Die Hälfte des Durchmessers.",
    "Area scales with r².": "Der Flächeninhalt wächst mit r².",
    "Common approximation.": "Gängige Näherung.",
    "Legs are base and height.": "Die Katheten sind Grundseite und Höhe.",
    "Use side²·√3/4.": "Nutze Seite²·√3/4.",
    "Area is linear in base.": "Der Flächeninhalt ist linear in der Grundseite.",
    "Base and height must be perpendicular.":
        "Grundseite und Höhe müssen senkrecht aufeinander stehen.",
    "SOH.": "GAH (Gegenkathete/Ankathete/Hypotenuse).",
    "Adjacent equals hypotenuse at 0°.": "Bei 0° ist Ankathete = Hypotenuse.",
    "Memorize the special angles.": "Die besonderen Winkel auswendig lernen.",
    "Use sin² + cos² = 1.": "Nutze sin² + cos² = 1.",
    "Top of the circle.": "Oben am Einheitskreis.",
    "Quadrant boundaries.": "Quadrantengrenzen.",
    "tan = sin/cos and cos 90° = 0.": "tan = sin/cos und cos 90° = 0.",
    "cos has period 360°.": "cos hat die Periode 360°.",
    "sin² + cos² = 1.": "sin² + cos² = 1.",
    "cos is even; sin is odd.": "cos ist gerade, sin ist ungerade.",
    "sin² = 1 → sin = ±1": "sin² = 1 → sin = ±1",
    "Plug 2 in.": "2 einsetzen.",
    "Plug x = 0.": "x = 0 einsetzen.",
    "1/x → 0 as x → ∞": "1/x → 0 für x → ∞",
    "It's the famous limit.": "Der berühmte Grenzwert.",
    "Factor numerator: (x−3)(x+3).": "Zähler faktorisieren: (x−3)(x+3).",
    "Power rule on each term; the constant vanishes.":
        "Potenzregel pro Term; die Konstante fällt weg.",
    "Multiply by the exponent, drop it by one.":
        "Mit dem Exponenten multiplizieren, dann um 1 verringern.",
    "f′(x) = 3x², then plug in 2.": "f′(x) = 3x², dann 2 einsetzen.",
    "Power rule with 1/2.": "Potenzregel mit Exponent 1/2.",
    "Standard derivative.": "Standard-Ableitung.",
    "Constants integrate to constant·x.": "Konstanten integrieren zu Konstante·x.",
    "Constant integrates to constant·x.": "Konstante integriert zu Konstante·x.",
    "Constants slide outside the integral.":
        "Konstanten dürfen vor das Integral gezogen werden.",
    "Reverse of d/dx(sin x).": "Umkehrung von d/dx(sin x).",
    "Reverse of d/dx(sin x) = cos x.": "Umkehrung von d/dx(sin x) = cos x.",
    "Power rule.": "Potenzregel.",
    "Power rule: x^4/4 + C.": "Potenzregel: x^4/4 + C.",
    "Add 1 to the exponent, divide by the new exponent, add C.":
        "Exponent +1, durch den neuen Exponenten teilen, +C.",
    "Treat −1 as a constant, integrate w.r.t. x.":
        "−1 als Konstante behandeln und nach x integrieren.",
    "Outer derivative times inner derivative.":
        "Äußere Ableitung mal innere Ableitung.",
    "Differentiate the outer function at the inner, then multiply by inner's derivative.":
        "Erst die äußere Funktion an der inneren ableiten, dann mit der Ableitung der inneren multiplizieren.",
    "Outer 3·u² times inner 2.": "Äußere 3·u² mal innere 2.",
    "Outer 3·u², inner is 2x.": "Äußere 3·u², innere 2x.",
    "Outer 4·u³, inner derivative is 3.": "Äußere 4·u³, innere Ableitung 3.",
    "Outer is cos, inner derivative is 2.": "Äußere cos, innere Ableitung 2.",
    "Inner u′ = 2": "Innere u′ = 2",
    "e^u stays, inner derivative is 3.": "e^u bleibt, innere Ableitung 3.",
    "Two perfect squares minus → product of sum and difference.":
        "Zwei Quadrate mit Minus → Produkt aus Summe und Differenz.",
    "Difference of squares with (2x)² and 5².":
        "Differenz von Quadraten mit (2x)² und 5².",
    "Pull out what's shared.": "Den gemeinsamen Faktor ausklammern.",
    "Recognize the pattern → square it back.":
        "Muster erkennen → wieder zur Quadratform.",
    "Use it whenever factoring is awkward.":
        "Nutze sie, wenn das Faktorisieren schwierig wird.",
    "GCD of 6 and 9.": "ggT von 6 und 9.",
    "Rise over run.": "Steigung = Höhenunterschied / Längenunterschied.",
    "Slope is zero.": "Die Steigung ist 0.",
    "y = mx + b.": "y = mx + b.",
    "No vertical change.": "Keine senkrechte Änderung.",
    "Look at the formula.": "Schau in die Formel.",
    "Memorize the 4/3.": "4/3 auswendig lernen.",
    "Volume scales with r³.": "Das Volumen wächst mit r³.",
    "Side cubed.": "Seite hoch drei.",
    "Base area times height.": "Grundfläche mal Höhe.",
    "Substitute the tangent identity.": "Tangens-Identität einsetzen.",
    "sin is odd.": "Sinus ist ungerade.",
    "cos is even.": "cos ist gerade.",
    "By the Pythagorean identity.": "Mit der trigonometrischen Pythagoras-Identität.",
    "(−)(−) = (+)": "(−)(−) = (+)",
    "Same sign → positive product. Different sign → negative.":
        "Gleiches Vorzeichen → positives Produkt. Unterschiedliches Vorzeichen → negatives.",

    # Multiple-choice option labels
    "The original price": "Der ursprüngliche Preis",
    "1% lower": "1 % niedriger",
    "1% higher": "1 % höher",
    "Depends on the price": "Hängt vom Preis ab",
    "They are equal": "Sie sind gleich",
    "Stays the same": "Bleibt gleich",
    "Doubles": "Verdoppelt sich",
    "Triple": "Verdreifacht sich",
    "Double": "Verdoppelt sich",
    "Halves": "Halbiert sich",
    "Quadruples": "Vervierfacht sich",
    "Four times": "Vier mal",
    "Sixteen times": "Sechzehn mal",
    "Two": "Zwei",
    "One": "Eins",
    "Zero": "Null",
    "Infinite": "Unendlich",
    "Infinity": "Unendlich",
    "Undefined": "Nicht definiert",
    "Cube": "Würfel",
    "Sphere": "Kugel",
    "Cylinder": "Zylinder",
    "Area": "Flächeninhalt",
    "Circumference": "Umfang",
    "ANNUAL · 25 % OFF": "JAHRESABO · 25 % RABATT",

    # Solution-step prose
    "Add 3: 3x = 12": "+3: 3x = 12",
    "Divide by 3: x = 4": ":3: x = 4",
    "Divide by 2: x = 4": ":2: x = 4",
    "Subtract 6: 2x = 8": "−6: 2x = 8",
    "Subtract 2x: 3x − 3 = 9": "−2x: 3x − 3 = 9",
    "Subtract 4 from both sides.": "Auf beiden Seiten 4 abziehen.",
    "Subtract 6 from both sides, then divide by 2.":
        "Auf beiden Seiten 6 abziehen, dann durch 2 teilen.",
    "Two minuses cancel.": "Zwei Minus heben sich auf.",
    "Absolute value strips the sign.": "Der Betrag entfernt das Vorzeichen.",
    "Substitute x = 0.": "x = 0 einsetzen.",
    "At x→3: 6": "Für x→3: 6",
    "Factor: (x − 2)(x − 3) = 0": "Faktorisierung: (x − 2)(x − 3) = 0",
    "Roots: x = 2 or x = 3": "Lösungen: x = 2 oder x = 3",
    "(x + 3)(x − 2) = 0": "(x + 3)(x − 2) = 0",
    "Δ = 9 − 4·2·(−5) = 9 + 40 = 49": "Δ = 9 − 4·2·(−5) = 9 + 40 = 49",
    "Δ < 0 → no real solutions": "Δ < 0 → keine reellen Lösungen",
    "Δ = 16 − 20 = −4": "Δ = 16 − 20 = −4",
    "Δ > 0 → two real roots. Δ = 0 → one. Δ < 0 → none in ℝ.":
        "Δ > 0 → zwei reelle Lösungen. Δ = 0 → eine. Δ < 0 → keine in ℝ.",
    "(2x)² − 5² = (2x−5)(2x+5)": "(2x)² − 5² = (2x−5)(2x+5)",
    "GCD = 3": "ggT = 3",
    "x² − 3² = (x−3)(x+3)": "x² − 3² = (x−3)(x+3)",
    "x² + 6x + 9 = (x + 3)²": "x² + 6x + 9 = (x + 3)²",
    "x² + 5x + 6 = (x + 2)(x + 3)": "x² + 5x + 6 = (x + 2)(x + 3)",
    "(x−3)(x+3)/(x−3) = x+3": "(x−3)(x+3)/(x−3) = x+3",
    "Power rule on each term; the constant vanishes.":
        "Potenzregel pro Term; die Konstante fällt weg.",
    "f′(x) = 3x²": "f′(x) = 3x²",
    "f′(2) = 12": "f′(2) = 12",
    "Derivative: (1/2)x^(−1/2) = 1/(2√x)":
        "Ableitung: (1/2)x^(−1/2) = 1/(2√x)",
    "This is one of the basic trig derivatives.":
        "Eine der grundlegenden trigonometrischen Ableitungen.",
    "5 · 4 · x³ = 20x³": "5 · 4 · x³ = 20x³",
    "d/dx(2x) = 2": "d/dx(2x) = 2",
    "d/dx(3x²) = 6x": "d/dx(3x²) = 6x",
    "d/dx(−7) = 0": "d/dx(−7) = 0",
    "Volume scales with r³.": "Das Volumen wächst mit r³.",
    "x − 3": "x − 3",
    "x + 1": "x + 1",
    "x + 2": "x + 2",
    "x − 6": "x − 6",
    "−1 + C": "−1 + C",
    "−x + C": "−x + C",
    "x + C": "x + C",
    "= x² + C": "= x² + C",
    "Reverse of d/dx(sin x) = cos x.": "Umkehrung von d/dx(sin x) = cos x.",
    "Useful in trigonometric limits.": "Nützlich bei trigonometrischen Grenzwerten.",
    "Useful in trigonometric limits.": "Nützlich bei trigonometrischen Grenzwerten.",
    "This is the Pythagorean identity.": "Das ist die trigonometrische Pythagoras-Identität.",
    "Direct from the unit circle.": "Direkt vom Einheitskreis.",
    "A full revolution returns to the start.":
        "Eine ganze Drehung führt zum Ausgang zurück.",
    "Every angle picks a unique point.": "Jeder Winkel ergibt einen eindeutigen Punkt.",
    "Or sin θ / cos θ.": "Oder sin θ / cos θ.",
    "x-coordinate at the top of the circle.":
        "x-Koordinate am höchsten Punkt des Einheitskreises.",
    "y-coordinate at the leftmost point.":
        "y-Koordinate am äußersten linken Punkt.",
    "Whenever cos θ ≠ 0.": "Immer wenn cos θ ≠ 0.",
    "Adjacent over hypotenuse.": "Ankathete durch Hypotenuse.",
    "Opposite over hypotenuse.": "Gegenkathete durch Hypotenuse.",
    "How much surface the circle covers.":
        "Wieviel Fläche der Kreis bedeckt.",
    "Distance around the circle.": "Wegstrecke um den Kreis herum.",
    "x-coordinate at the top of the circle.":
        "x-Koordinate am höchsten Punkt des Einheitskreises.",
    "+ for increase, − for decrease.":
        "+ für Erhöhung, − für Verringerung.",
    "Multiply across to share a denominator, then add the tops.":
        "Über Kreuz multiplizieren, dann die Zähler addieren.",
    "Divide numerator and denominator by their common factor.":
        "Zähler und Nenner durch den gemeinsamen Faktor teilen.",
    "Pull out what's shared.": "Den gemeinsamen Faktor ausklammern.",
    "Add 1 to the exponent, divide by the new exponent, add C.":
        "Exponent + 1, durch den neuen Exponenten teilen, +C.",
    "Constants slide outside the integral.":
        "Konstanten dürfen vor das Integral gezogen werden.",
    "Mathio": "Mathio",  # Brand name — never localised.
    "Bring down the exponent, subtract one.":
        "Den Exponenten als Faktor nach vorne ziehen und um 1 verringern.",
    "Constants don't change.": "Konstanten ändern sich nicht.",
    "Difference of squares.": "Differenz zweier Quadrate.",
    "Differentiate term by term.": "Term für Term ableiten.",
    "Perfect square.": "Vollständiges Quadrat.",
    "θ": "θ",
    "π": "π",
    "x": "x",
    "Cosine": "Kosinus",
    "sin θ": "sin θ",
    "cos θ": "cos θ",
    "Inner u′ = 2": "Innere u′ = 2",
    "Pythagorean": "Pythagoras",
    "(8 − 2) / (3 − 1).": "(8 − 2) / (3 − 1).",
    "C = 2πr.": "C = 2πr.",
    "C = 2π·5 = 10π": "C = 2π·5 = 10π",
    "(4/3)πr³.": "(4/3)πr³.",
    "(4/3)π·27 = 36π": "(4/3)π·27 = 36π",
    "πr²h.": "πr²h.",
    "π · 4 · 5 = 20π": "π · 4 · 5 = 20π",
    "s³.": "s³.",
    "1³.": "1³.",
    "A = πr².": "A = πr².",
    "A = π·9 = 9π": "A = π·9 = 9π",
    "A = ½ · 10 · 6 = 30": "A = ½ · 10 · 6 = 30",
    "A = ½ · 5 · 12 = 30": "A = ½ · 5 · 12 = 30",
    "A = 2²·√3/4 = √3": "A = 2²·√3/4 = √3",
    "A = ½bh — same b, same h → same A.": "A = ½bh — gleiches b, gleiches h → gleiches A.",
    "½ · 2b · h = 2 · (½bh) = double": "½ · 2b · h = 2 · (½bh) = doppelt",
    "s = (a+b+c)/2 is the semi-perimeter.": "s = (a+b+c)/2 ist der halbe Umfang.",
    "c is the side opposite the right angle.": "c ist die der rechten Ecke gegenüberliegende Seite.",
    "b² = c² − a²": "b² = c² − a²",
    "b = 12": "b = 12",
    "c = 10": "c = 10",
    "c = √25 = 5": "c = √25 = 5",
    "13² − 5² = 169 − 25 = 144": "13² − 5² = 169 − 25 = 144",
    "25 + 144 = 169 = 13²": "25 + 144 = 169 = 13²",
    "1² + 1² = 2.": "1² + 1² = 2.",
    "d² = 2": "d² = 2",
    "d = √2": "d = √2",
    "r = d/2 = 4": "r = d/2 = 4",
    "Slope through (1, 2) and (3, 8).": "Steigung durch (1, 2) und (3, 8).",
    "y = 4·2 + 1 = 9": "y = 4·2 + 1 = 9",
    "m = 6/2 = 3": "m = 6/2 = 3",
    "m = 0": "m = 0",
    "m is the slope, b is the y-intercept.": "m ist die Steigung, b der y-Achsenabschnitt.",
    "At x = 0: y = −5": "Bei x = 0: y = −5",
    "For any x, y = 3 → horizontal.": "Für jedes x ist y = 3 → waagerecht.",
    "Δy = 0": "Δy = 0",
    "lim x→0 sin(x)/x = 1": "lim x→0 sin(x)/x = 1",
    "0 + 5 = 5": "0 + 5 = 5",
    "3·2 + 1 = 7": "3·2 + 1 = 7",
    "12 ÷ 4 = 3": "12 ÷ 4 = 3",
    "8 − 6 = 2": "8 − 6 = 2",
    "5 + 3 · 4": "5 + 3 · 4",
    "(5 + 3) · 4": "(5 + 3) · 4",
    "2 · 3 + 5": "2 · 3 + 5",
    "3 + 4 = 7": "3 + 4 = 7",
    "2 · 3 = 6": "2 · 3 = 6",
    "4 · 5 = 20": "4 · 5 = 20",
    "3 + 8 = 11": "3 + 8 = 11",
    "20 − 4 + 1": "20 − 4 + 1",
    "−7 + 3 = −4": "−7 + 3 = −4",
    "3 − (−2) = 3 + 2 = 5": "3 − (−2) = 3 + 2 = 5",
    "−1 > −5 > −10 > −100": "−1 > −5 > −10 > −100",
    "0.2 · 80 = 16": "0,2 · 80 = 16",
    "80 · 0.75 = 60": "80 · 0,75 = 60",
    "1.10 · 0.90 = 0.99": "1,10 · 0,90 = 0,99",
    "= 1% lower than original": "= 1 % niedriger als der Ausgangspreis",
    "200% = 2.": "200 % = 2.",
    "2 · 5 = 10": "2 · 5 = 10",
    "15/60 = 0.25 = 25%": "15/60 = 0,25 = 25 %",
    "20/100 = 0.2.": "20/100 = 0,2.",
    "1/2 = 3/6": "1/2 = 3/6",
    "1/3 = 2/6": "1/3 = 2/6",
    "Sum: 5/6": "Summe: 5/6",
    "Sum: 6x + 2": "Summe: 6x + 2",
    "1/2 + 1/2 = 1": "1/2 + 1/2 = 1",
    "GCD(8,12) = 4": "ggT(8,12) = 4",
    "8/12 = 2/3": "8/12 = 2/3",
    "3/4 = 6/8": "3/4 = 6/8",
    "6/8 > 5/8": "6/8 > 5/8",
    "2/3 = 4/6": "2/3 = 4/6",
    "4/6 − 1/6 = 3/6 = 1/2": "4/6 − 1/6 = 3/6 = 1/2",
    "2/4 = 1/2": "2/4 = 1/2",
    "5⁻² = 1/5² = 1/25": "5⁻² = 1/5² = 1/25",
    "x⁵⁻² = x³": "x⁵⁻² = x³",
    "2³⁺⁴ = 2⁷ = 128": "2³⁺⁴ = 2⁷ = 128",
    "3²·³ = 3⁶ = 729": "3²·³ = 3⁶ = 729",
    "4³ = 64": "4³ = 64",
    "Add 3: 3x = 12": "+3: 3x = 12",
    "3x = 15": "3x = 15",
    "x = 7 − 4 = 3": "x = 7 − 4 = 3",
    "−2x = −8": "−2x = −8",
    "x² = 9": "x² = 9",
    "x = ±3": "x = ±3",
    "x = −3 or x = 2": "x = −3 oder x = 2",
    "1·1·1 = 1": "1·1·1 = 1",
    "5 + 12 = 17": "5 + 12 = 17",
    "3 + 2 = 5": "3 + 2 = 5",
    "4 · 2 = 8": "4 · 2 = 8",
    "7 · 2 = 14": "7 · 2 = 14",
    "3² + 4² = 25": "3² + 4² = 25",
    "6² + 8² = 100": "6² + 8² = 100",
    "20x³": "20x³",
    "5x³": "5x³",
    "4x⁵": "4x⁵",
    "3 + 2 = 5": "3 + 2 = 5",
    "3(2x + 3)": "3(2x + 3)",
    "3(x²+1)² · 2x = 6x(x²+1)²": "3(x²+1)² · 2x = 6x(x²+1)²",
    "Product: 3(2x+1)² · 2 = 6(2x+1)²": "Produkt: 3(2x+1)² · 2 = 6(2x+1)²",
    "4(3x+2)³ · 3 = 12(3x+2)³": "4(3x+2)³ · 3 = 12(3x+2)³",
    "cos(2x) · 2 = 2cos(2x)": "cos(2x) · 2 = 2cos(2x)",
    "e^(3x) · 3 = 3e^(3x)": "e^(3x) · 3 = 3e^(3x)",
    "cos(−x) = cos(x) for all x.": "cos(−x) = cos(x) für alle x.",
    "sin(−x) = −sin(x)": "sin(−x) = −sin(x)",
    "−sin(x) + sin(x) = 0": "−sin(x) + sin(x) = 0",
    "0°": "0°",
    "90°": "90°",
    "180°": "180°",
    "360°": "360°",
    "(2r)² = 4r²": "(2r)² = 4r²",
    "(2r)³ = 8r³": "(2r)³ = 8r³",
    "Area is 4× larger.": "Der Flächeninhalt ist 4× so groß.",
    "d/du(u³) = 3u²": "d/du(u³) = 3u²",
    "Power rule: x^4/4 + C.": "Potenzregel: x^4/4 + C.",
    "∫ 5 dx = 5x + C": "∫ 5 dx = 5x + C",
    "∫ x³ dx = x⁴/4 + C": "∫ x³ dx = x⁴/4 + C",
    "∫ 2x dx = 2 · x²/2 + C": "∫ 2x dx = 2 · x²/2 + C",
    "∫ cos x dx = sin x + C": "∫ cos x dx = sin x + C",
    "∫ (−1) dx = −x + C": "∫ (−1) dx = −x + C",
    "Works when f is continuous at a.": "Gilt, wenn f bei a stetig ist.",
    "√x = x^(1/2)": "√x = x^(1/2)",
    "Sum: 6x + 2": "Summe: 6x + 2",
    "Multiply both by 2: 3-4-5 triple.": "Beide mal 2: 3-4-5-Tripel.",
    "Standard derivative.": "Standard-Ableitung.",
    "−1": "−1",
    "−5": "−5",
    "−10": "−10",
    "−100": "−100",
    "0": "0",
    "4": "4",
    "6": "6",
    "8": "8",
    "Two": "Zwei",
    "Left-to-right inside the same level.":
        "Bei gleicher Priorität von links nach rechts.",
    "x = 1": "x = 1",
    "x = 3": "x = 3",
    "x = 4": "x = 4",
    "x = 5": "x = 5",
    "x = 7": "x = 7",
    "tan 90° is undefined (division by zero).":
        "tan 90° ist nicht definiert (Division durch null).",
    "tan 90° is undefined (division by zero).": "tan 90° ist nicht definiert (Division durch null).",
    "tan 45° = 1": "tan 45° = 1",
    "sin 30° = 1/2": "sin 30° = 1/2",
    "sin 45° = cos 45°.": "sin 45° = cos 45°.",
    "sin 90° = 1": "sin 90° = 1",
    "sin 180° = 0": "sin 180° = 0",
    "cos 0° = 1": "cos 0° = 1",
    "cos 90° = 0": "cos 90° = 0",
    "sin θ = 3/5": "sin θ = 3/5",
    "cos² = 1 − 9/25 = 16/25": "cos² = 1 − 9/25 = 16/25",
    "cos = 4/5 (Q1)": "cos = 4/5 (Q1)",
    "(sin θ / cos θ) · cos θ = sin θ": "(sin θ / cos θ) · cos θ = sin θ",
    "±1": "±1",
    "√2/2": "√2/2",
    "√3/2": "√3/2",
    "1/2": "1/2",
    "3/4": "3/4",
    "5/8": "5/8",
    "π ≈ 3.14159…": "π ≈ 3,14159…",
}

# Strings whose value is identical in DE: pure math, single letters, etc.
# Detected by absence of letters that would translate.

def is_passthrough(s: str) -> bool:
    """Decide if this string is identical in EN and DE without manual review.

    Heuristic: contains no English-only word characters of length ≥ 3.
    """
    # Strip math/punctuation; if what's left is short, it's passthrough.
    letters = re.findall(r"[A-Za-z]+", s)
    if not letters:
        return True   # pure math/symbols
    # Single-char identifiers (x, y, c, b, m, r) are universal.
    if all(len(w) <= 2 for w in letters):
        return True
    return False


def main() -> None:
    with open("Localizable.xcstrings", encoding="utf-8") as f:
        data = json.load(f)
    xc_keys = set(data["strings"].keys())

    # Re-discover all candidate strings (same logic as the audit script).
    candidates: set[str] = set()
    pat_named = [
        r'title:\s*"([^"\\]+)"',
        r'subtitle:\s*"([^"\\]+)"',
        r'intro:\s*"([^"\\]+)"',
        r'name:\s*"([^"\\]+)"',
        r'explanation:\s*"([^"\\]+)"',
        r'prompt:\s*"([^"\\]+)"',
        r'hint:\s*"([^"\\]+)"',
        r'label:\s*"([^"\\]+)"',
        r'LocalizedStringResource\(\s*"([^"\\]+)"',
        r'String\(localized:\s*"([^"\\]+)"',
    ]
    pat_array = [r'solutionSteps:\s*\[([^\]]+)\]']
    pat_text = (r'(?:Text|Button|navigationTitle|Picker|Toggle|Stepper|Section|Label)'
                r'\(\s*"([^"\\]+)"')

    for fname in os.listdir("."):
        if not fname.endswith(".swift"):
            continue
        src = open(fname, encoding="utf-8").read()
        for pat in pat_named:
            candidates.update(m.group(1) for m in re.finditer(pat, src))
        for pat in pat_array:
            for arr in re.finditer(pat, src):
                candidates.update(re.findall(r'"([^"\\]+)"', arr.group(1)))
        candidates.update(m.group(1) for m in re.finditer(pat_text, src))

    missing = sorted(s for s in candidates if s not in xc_keys)

    added_prose, added_math, missing_review = 0, 0, []
    for s in missing:
        if s in PROSE:
            de_value = PROSE[s]
            added_prose += 1
        elif is_passthrough(s):
            de_value = s
            added_math += 1
        else:
            missing_review.append(s)
            continue
        data["strings"][s] = {
            "localizations": {
                "de": {"stringUnit": {"state": "translated", "value": de_value}}
            }
        }

    if missing_review:
        print(f"!! {len(missing_review)} prose strings need a DE translation; "
              "add them to PROSE in this script:")
        for s in missing_review:
            print(f"    {s!r}: \"\",")
        sys.exit(1)

    with open("Localizable.xcstrings", "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"OK: added {added_prose} prose translations + {added_math} math passthroughs")
    print(f"xcstrings now: {len(data['strings'])} keys")


if __name__ == "__main__":
    main()
