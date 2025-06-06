library;

import 'dart:async';
// For htmlEscape if needed, though XmlElement handles it.

import 'package:xml/xml.dart' as xml_pkg;
import 'package:apktool_dart/src/xmlpull/xml_pull_parser.dart';

// Assuming AXmlResourceParser is correctly imported from its location
import 'axml_resource_parser.dart';
import 'typed_value.dart';

class ManifestXmlSerializer {
  final AXmlResourceParser _parser;

  ManifestXmlSerializer(this._parser);

  Future<String> buildXmlDocumentToString() async {
    final List<xml_pkg.XmlNode> nodeStack = []; // Root will be XmlDocument
    xml_pkg.XmlDocument? document;

    int eventType = _parser.getEventType();
    if (eventType == -1) {
      eventType = await _parser.next();
    }

    // First event must be START_DOCUMENT
    if (eventType == XmlPullParser.kStartDocument) {
      // The XmlDocument is implicitly created when we add the root element.
      // For now, we just advance past START_DOCUMENT.
      eventType = await _parser.next();
    }

    xml_pkg.XmlElement? currentParent;

    while (eventType != XmlPullParser.kEndDocument) {
      switch (eventType) {
        case XmlPullParser.kStartTag:
          final attributes = <xml_pkg.XmlAttribute>[];
          final String? tagPrefix = _parser.getPrefix();
          final String tagName = _parser.getName() ?? "unknown";
          final String? tagNamespaceUri = _parser.getNamespace();

          final name = xml_pkg.XmlName(tagName, tagPrefix);

          for (int i = 0; i < _parser.getAttributeCount(); i++) {
            final String? attrPrefix = _parser.getAttributePrefix(i);
            final String attrNameStr = _parser.getAttributeName(i) ?? "attr$i";
            String attrValue = _parser.getAttributeValue(i) ?? "";

            // Try to resolve resource references
            final valueType = _parser.getAttributeValueType(i);
            if (valueType == TypedValue.TYPE_REFERENCE &&
                attrValue.startsWith('@0x')) {
              try {
                // Parse hex resource ID
                final hexStr = attrValue.substring(3); // Remove @0x
                final resId = int.parse(hexStr, radix: 16);

                // Try to resolve through ResTable
                final resTable = _parser.getResTable();
                if (resTable != null) {
                  final resolved = resTable.resolveReference(resId);
                  if (resolved != null) {
                    attrValue = resolved;
                  }
                }
              } catch (e) {
                // Keep original value if resolution fails
              }
            }
            // final String? attrNsUri = _parser.getAttributeNamespace(i); // Not directly used by XmlAttribute constructor like this

            attributes.add(
              xml_pkg.XmlAttribute(
                xml_pkg.XmlName(attrNameStr, attrPrefix),
                attrValue,
              ),
            );
          }

          final element = xml_pkg.XmlElement(
            name,
            attributes,
            [],
            false,
          ); // isSelfClosing = false
          if (tagNamespaceUri != null && tagNamespaceUri.isNotEmpty) {
            // Manually declare namespace on element if XmlName didn't handle it via prefix context
            // XmlName with prefix should ideally resolve against parent scope, but here we can be explicit if needed.
            // For now, assume prefix in XmlName is sufficient if namespaces are correctly pushed/popped in parser.
          }

          if (nodeStack.isEmpty) {
            // This is the root element
            document = xml_pkg.XmlDocument([element]);
            currentParent = element;
          } else {
            (nodeStack.last as xml_pkg.XmlElement).children.add(element);
            currentParent = element;
          }
          nodeStack.add(element);
          break;

        case XmlPullParser.kEndTag:
          if (nodeStack.isNotEmpty) nodeStack.removeLast();
          currentParent = nodeStack.isNotEmpty
              ? nodeStack.last as xml_pkg.XmlElement
              : null;
          break;

        case XmlPullParser.kText:
          final String? text = _parser.getText();
          if (text != null && text.isNotEmpty) {
            // Add even if only whitespace, XML spec allows
            currentParent?.children.add(xml_pkg.XmlText(text));
          }
          break;

        case XmlPullParser.kCdsect:
          final String? cdataText = _parser.getText();
          if (cdataText != null) {
            currentParent?.children.add(xml_pkg.XmlCDATA(cdataText));
          }
          break;

        default:
          break;
      }
      eventType = await _parser.next();
    }

    if (document == null &&
        nodeStack.isNotEmpty &&
        nodeStack.first is xml_pkg.XmlElement) {
      // If only one root element was parsed and no explicit document START/END
      document = xml_pkg.XmlDocument([nodeStack.first]);
    }

    return document?.toXmlString(pretty: true, indent: '  ', newLine: '\n') ??
        '';
  }
}
