// Application schema grammar versus the supported QtGui parser; guest-only tool.
#include <QColor>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QTextStream>

int main(int argc, char **argv) {
    if (argc != 2)
        return 2;
    QFile file(QString::fromLocal8Bit(argv[1]));
    if (!file.open(QIODevice::ReadOnly))
        return 2;
    QString pattern;
    for (const auto &value : QJsonDocument::fromJson(file.readAll()).object()["paths"].toArray()) {
        const auto node = value.toObject();
        if (node["path"].toArray() == QJsonArray{"wallpaper", "fillColor"})
            pattern = node["stringPattern"].toString();
    }
    if (pattern.isEmpty())
        return 2;
    QRegularExpression expression(QRegularExpression::anchoredPattern(pattern));
    if (!expression.isValid())
        return 2;
    QStringList cases = {"", "not-a-color", "red\n", "#fff\n", "#ggg", "rebeccaPurple",
                         QString(256, ' ') + "red", QString(252, ' ') + "red",
                         QString(253, ' ') + "red", "#fff ", " light blue ", "\tRED\t"};
    for (const auto &name : QColor::colorNames()) {
        cases << name << name.toUpper() << (" " + name + "\t");
        QString spaced;
        for (const auto ch : name)
            spaced += ch + QStringLiteral(" \t");
        cases << spaced;
    }
    for (int size = 0; size <= 16; ++size)
        cases << ('#' + QString(size, 'a')) << ('#' + QString(size, 'F'));
    for (const auto &input : cases) {
        if (expression.match(input).hasMatch() != QColor::fromString(input).isValid()) {
            QTextStream(stderr) << "COLOR_PARITY: mismatch (input omitted)\n";
            return 1;
        }
    }
    QTextStream(stdout) << "SETTINGS_COLOR_PARITY: PASS (" << cases.size() << " cases)\n";
    return 0;
}
