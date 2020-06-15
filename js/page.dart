import 'dart:html';
import 'package:json_to_dart/json_to_dart.dart';
import 'package:json_ast/json_ast.dart';
import 'package:json_to_dart/syntax.dart';
import 'package:json_to_dart/helpers.dart';
import './json.dart';
import './ace.dart';
import './highlight.dart';

typedef ACEEditorAnnotation _annotationMapper(Warning w);

void main() {
  final ButtonElement convertButton =
      document.querySelector('button[type="submit"]');
  final highlightedDartCode = document.querySelector('pre code.dart');
  final CheckboxInputElement usePrivateFieldsCheckbox =
      document.querySelector('#private-fields');
  final CheckboxInputElement useNewKeyword =
      document.querySelector('#new-keyword');
  final CheckboxInputElement useThisKeyword =
      document.querySelector('#this-keyword');
  final CheckboxInputElement useCollectionLiterals =
      document.querySelector('#collection-literals');
  final CheckboxInputElement makePropertiesFinal =
      document.querySelector('#final');
  final CheckboxInputElement makePropertiesRequired =
      document.querySelector('#required');
  final ButtonElement copyClipboardButton =
      document.querySelector('#copy-clipboard');
  final TextAreaElement hiddenElement = document.querySelector('#hidden-dart');
  final InputElement dartClassNameInput =
      document.querySelector('#dartClassName');
  final Element boldElement = document.querySelector('#invalid-dart');
  final Element jsonEditor = document.querySelector('#jsonEditor');
  final editor = ace.edit(jsonEditor);
  editor.setTheme('ace/theme/github');
  editor.getSession().setMode("ace/mode/json");
  editor.getSession().setOption("useWorker", false);
  copyClipboardButton.onClick.listen((MouseEvent event) {
    event.preventDefault();
    event.stopPropagation();
    if (!copyClipboardButton.disabled) {
      hiddenElement.select();
      document.execCommand("Copy");
    }
  });
  convertButton.onClick.listen((MouseEvent event) {
    event.preventDefault();
    event.stopPropagation();
    var dartClassName = dartClassNameInput.value;
    if (dartClassName.trim() == '') {
      dartClassName = 'Autogenerated';
    }
    var syntaxError = false;
    var invalidDart = false;
    var json = editor.getValue();
    dynamic obj;
    try {
      obj = JSON.parse(json);
    } catch (e) {
      syntaxError = true;
      window.alert('The json provider has syntax errors');
    }
    if (!syntaxError) {
      // beautify
      json = JSON.stringify(obj, null, 4);
      editor.setValue(json);
      editor.getSession().clearAnnotations();
      final modelGenerator = new ModelGenerator(
        dartClassName,
        usePrivateFieldsCheckbox.checked,
        useNewKeyword.checked,
        useThisKeyword.checked,
        useCollectionLiterals.checked,
        makePropertiesRequired.checked,
        makePropertiesFinal.checked,
      );
      DartCode dartCode;
      try {
        dartCode = modelGenerator.generateDartClasses(json);
        boldElement.style.display = 'none';
      } catch (e) {
        invalidDart = true;
      }
      if (invalidDart) {
        try {
          dartCode = modelGenerator.generateUnsafeDart(json);
        } catch (e) {
          window.alert(
              'Cannot generate dart code. Please check the project caveats.');
          hiddenElement.value = '';
          highlightedDartCode.text = '';
          copyClipboardButton.attributes
              .putIfAbsent('disabled', () => 'disabled');
          print(e);
          return;
        }
        boldElement.style.display = 'block';
      }
      if (dartCode.warnings != null) {
        try {
          final annotationMapper = buildAnnotationMapper(
              parse(json, Settings(source: 'input.json')));
          final annotations = dartCode.warnings
              .map<ACEEditorAnnotation>(annotationMapper)
              .where((a) => a != null)
              .toList();
          editor.getSession().setAnnotations(annotations);
        } catch (e) {
          print('Error attempting to set annotations: $e');
        }
      }
      hiddenElement.value = dartCode.code;
      highlightedDartCode.text = dartCode.code;
      copyClipboardButton.attributes.remove('disabled');
      hljs.highlightBlock(highlightedDartCode);
    } else {
      hiddenElement.value = '';
      highlightedDartCode.text = '';
      copyClipboardButton.attributes.putIfAbsent('disabled', () => 'disabled');
    }
  });
}

_annotationMapper buildAnnotationMapper(Node root) {
  return (Warning w) => annotationForWarning(root, w);
}

final _arrayElementRegExp = new RegExp(r"\[([0-9]+)\]");

ACEEditorAnnotation annotationForWarning(Node root, Warning w) {
  var node = root;
  final paths = w.path.split('/');
  paths.where((p) => p.trim() != '').forEach((p) {
    if (_arrayElementRegExp.hasMatch(p)) {
      var splittedPath = p.split('[');
      // navigate property
      node = navigateNode(node, splittedPath[0]);
      splittedPath = splittedPath[1].split(']');
      // navigate index
      node = navigateNode(node, splittedPath[0]);
    } else {
      node = navigateNode(node, p);
    }
  });
  ACEEditorAnnotation annotation;
  print('node: ${node}');
  if (node is LiteralNode) {
    annotation = ACEEditorAnnotation();
    print('new annotation at line ${node.loc.start.line}');
    print('new annotation at column ${node.loc.start.column}');
    annotation.row = node.loc.start.line - 1;
    annotation.column = node.loc.start.column - 1;
    annotation.text = w.warning;
    annotation.type = 'error';
    return annotation;
  }
  return annotation;
}
