/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2017 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.xml.xml_dom;

import std.array : Appender, split;
import std.typecons : Flag;
public import std.typecons : No, Yes;

debug(debug_pham_xml_xml_dom) import std.stdio : writeln;

import pham.utl.utl_dlink_list;
import pham.utl.utl_enum_set : EnumSet;
import pham.utl.utl_object : shortClassName, singleton;
import pham.xml.xml_buffer;
import pham.xml.xml_entity_table;
import pham.xml.xml_exception;
import pham.xml.xml_message;
import pham.xml.xml_object;
import pham.xml.xml_parser;
import pham.xml.xml_reader;
import pham.xml.xml_string;
import pham.xml.xml_type;
import pham.xml.xml_util;
import pham.xml.xml_writer;

@safe:

enum XmlParseOptionFlag : ubyte
{
    none = 0,
    preserveWhitespace = 1 << 0,
    validate = 1 << 1,
}

struct XmlParseOptions(S = string)
if (isXmlString!S)
{
public:
    alias XmlSaxAttributeEvent = bool delegate(XmlNode!S parent, XmlAttribute!S attribute);
    alias XmlSaxElementBeginEvent = void delegate(XmlNode!S parent, XmlElement!S element);
    alias XmlSaxElementEndEvent = bool delegate(XmlNode!S parent, XmlElement!S element);
    alias XmlSaxNodeEvent = bool delegate(XmlNode!S parent, XmlNode!S node);

    XmlSaxAttributeEvent onSaxAttributeNode; // Return true to keep attribute node
    XmlSaxElementBeginEvent onSaxElementNodeBegin;
    XmlSaxElementEndEvent onSaxElementNodeEnd; // Return true to keep element node
    XmlSaxNodeEvent onSaxOtherNode; // Return true to keep xml node

@safe:

public:
    pragma (inline, true)
    @property bool preserveWhitespace() const nothrow
    {
        return flags.on(XmlParseOptionFlag.preserveWhitespace);
    }

    @property void preserveWhitespace(bool value) nothrow
    {
        flags.set(XmlParseOptionFlag.preserveWhitespace, value);
    }

    pragma (inline, true)
    @property bool validate() const nothrow
    {
        return flags.on(XmlParseOptionFlag.validate);
    }

    @property void validate(bool value) nothrow
    {
        flags.set(XmlParseOptionFlag.validate, value);
    }

public:
    EnumSet!XmlParseOptionFlag flags = EnumSet!XmlParseOptionFlag(XmlParseOptionFlag.validate);
}

/** A type indicator, nodeType, of an XmlNode object
    $(XmlNodeType.element) An element. For example: <item></item> or <item/>
    $(XmlNodeType.attribute) An attribute. For example: id='123'
    $(XmlNodeType.text) The text content of a node
    $(XmlNodeType.cdata) A CDATA section. For example: <![CDATA[my escaped text]]>
    $(XmlNodeType.entityReference) A reference to an entity. For example: &num;
    $(XmlNodeType.entity) An entity declaration. For example: <!ENTITY...>
    $(XmlNodeType.processingInstruction) A processing instruction. For example: <?pi test?>
    $(XmlNodeType.comment) A comment. For example: <!-- my comment -->
    $(XmlNodeType.document) A document object that, as the root of the document tree, provides access to the entire XML document
    $(XmlNodeType.documentType) The document type declaration, indicated by the following tag. For example: <!DOCTYPE...>
    $(XmlNodeType.documentFragment) A document fragment.
    $(XmlNodeType.notation) A notation in the document type declaration. For example, <!NOTATION...>
    $(XmlNodeType.whitespace) White space between markup
    $(XmlNodeType.significantWhitespace) White space between markup in a mixed content model or white space within the xml:space="preserve" scope
    $(XmlNodeType.declaration) The XML declaration. For example: <?xml version='1.0'?>
    $(XmlNodeType.documentTypeAttributeList) An attribute-list declaration. For example: <!ATTLIST...>
    $(XmlNodeType.documentTypeElement) An element declaration. For example: <!ELEMENT...>
*/
enum XmlNodeType : ubyte
{
    unknown = 0,
    element = 1,
    attribute = 2,
    text = 3,
    cdata = 4,
    entityReference = 5,
    entity = 6,
    processingInstruction = 7,
    comment = 8,
    document = 9,
    documentType = 10,
    documentFragment = 11,
    notation = 12,
    whitespace = 13,
    significantWhitespace = 14,
    declaration = 17,
    documentTypeAttributeList = 20,
    documentTypeElement = 21,
}

/** A state of a XmlNodeList struct
    $(XmlNodeListType.attributes) A node list represents of attribute nodes
    $(XmlNodeListType.childNodes) A node list represents of xml nodes except attribute node
    $(XmlNodeListType.childNodesDeep) Similar to childNodes but it includes all sub-nodes
    $(XmlNodeListType.flat) A simple copy array of nodes
*/
enum XmlNodeListType : ubyte
{
    attributes,
    childNodes,
    childNodesDeep,
    flat,
}

class XmlNodeFilterContext(S = string) : XmlObject!S
{
nothrow @safe:

public:
    enum WildMatch : ubyte
    {
        name,
        localName,
        namespaceUri,
    }

    static immutable S wildMatchText = "*";

public:
    this(XmlDocument!S document, XmlNodeType nodeType, const(C)[] name, Object context) pure
    {
        this._document = document;
        this._nodeType = nodeType;
        this._name = name;
        this._localName = null;
        this._namespaceUri = null;
        this.context = context;
        this.equalName = document.equalName;
        this._wildMatches.set(WildMatch.name, name == wildMatchText);
    }

    this(XmlDocument!S document, XmlNodeType nodeType, const(C)[] localName, const(C)[] namespaceUri, Object context) pure
    {
        this._document = document;
        this._nodeType = nodeType;
        this._name = null;
        this._localName = localName;
        this._namespaceUri = namespaceUri;
        this.context = context;
        this.equalName = document.equalName;
        this._wildMatches.set(WildMatch.localName, localName == wildMatchText);
        this._wildMatches.set(WildMatch.namespaceUri, namespaceUri == wildMatchText);
    }

    final bool matchByLocalNameUri(Object context, XmlNode!S node) const
    {
        return (_nodeType == node.nodeType) &&
            (_wildMatches.on(WildMatch.localName) || equalName(_localName, node.localName)) &&
            (_wildMatches.on(WildMatch.namespaceUri) || equalName(_namespaceUri, node.namespaceUri));
    }

    final bool matchByName(Object context, XmlNode!S node) const
    {
        return (_nodeType == node.nodeType) &&
            (_wildMatches.on(WildMatch.name) || equalName(_name, node.name));
    }

    @property final XmlDocument!S document() pure
    {
        return _document;
    }

    @property final const(C)[] localName() const pure
    {
        return _localName;
    }

    @property final const(C)[] name() const pure
    {
        return _name;
    }

    @property final const(C)[] namespaceUri() const pure
    {
        return _namespaceUri;
    }

    @property final XmlNodeType nodeType() const pure
    {
        return _nodeType;
    }

    @property final EnumSet!WildMatch wildMatches() const pure
    {
        return _wildMatches;
    }

public:
    Object context;
    XmlDocument!S.EqualName equalName;

protected:
    XmlDocument!S _document;
    const(C)[] _localName;
    const(C)[] _name;
    const(C)[] _namespaceUri;
    EnumSet!WildMatch _wildMatches;
    XmlNodeType _nodeType;
}

/** A root xml node for all xml node objects
*/
abstract class XmlNode(S = string) : XmlObject!S
{
@safe:

public:
    /**
     * Returns attributes of this node
     * If node does not have any attributes, returns an empty node list
     * Params:
     *   context = caller context info; can be null
     * Returns:
     *   XmlNodeList with all its attributes
     */
    final XmlNodeList!S getAttributes(Object context)
    {
        return XmlNodeList!S(this, XmlNodeListType.attributes, null, context);
    }

    /**
     * Same as getAttributes with parameter context=null
     */
    final XmlNodeList!S getAttributes()
    {
        return getAttributes(null);
    }

    /**
     * Returns child-nodes/subchild-nodes of this node
     * If node does not have any child-nodes, returns an empty node list
     * Params:
     *   context = caller context info; can be null
     *   deep = if true, it will also return all subchild-nodes
     * Returns:
     *   XmlNodeList with all its child-nodes and all subchild-nodes if requested
     */
    final XmlNodeList!S getChildNodes(Object context,
        Flag!"deep" deep = No.deep)
    {
        if (deep)
            return XmlNodeList!S(this, XmlNodeListType.childNodesDeep, null, context);
        else
            return XmlNodeList!S(this, XmlNodeListType.childNodes, null, context);
    }

    /**
     * Same as getChildNodes with parameters context=null and deep=No
     */
    final XmlNodeList!S getChildNodes()
    {
        return getChildNodes(null, No.deep);
    }

    /**
     * Returns child-elements/subchild-elements of this node
     * If node does not have any child-elements, returns an empty node list
     * Params:
     *   context = caller context info; can be null
     *   deep = if true, it will also return all subchild-elements
     * Returns:
     *   XmlNodeList with all its child-elements and all subchild-elements if requested
     */
    final XmlNodeList!S getElements(Object context,
        Flag!"deep" deep = No.deep)
    {
        return getElementsByTagName(XmlNodeFilterContext!S.wildMatchText, context, deep);
    }

    /**
     * Same as getElements with parameters context=null and deep=No
     */
    final XmlNodeList!S getElements()
    {
        return getElements(null, No.deep);
    }

    /**
     * Same as getElements except that the elements must be matched with filtered parameter name
     * Params:
     *   name = a name to be filtered
     *   context = caller context info; can be null
     *   deep = if true, it will also include all subchild-elements
     */
    final XmlNodeList!S getElementsByTagName(const(C)[] name,
        Object context = null,
        Flag!"deep" deep = Yes.deep)
    {
        auto filterContext = new XmlNodeFilterContext!S(document, XmlNodeType.element, name, context);
        if (deep)
            return XmlNodeList!S(this, XmlNodeListType.childNodesDeep, &filterContext.matchByName, filterContext);
        else
            return XmlNodeList!S(this, XmlNodeListType.childNodes, &filterContext.matchByName, filterContext);
    }

    /**
     * Same as getElements except that the elements must be matched with filtered parameters localName and namespaceUri
     * Params:
     *   localName = a localName to be filtered
     *   namespaceUri = a namespaceUri to be filtered
     *   context = caller context info; can be null
     *   deep = if true, it will also include all subchild-elements
     */
    final XmlNodeList!S getElementsByTagName(const(C)[] localName, const(C)[] namespaceUri,
        Object context = null,
        Flag!"deep" deep = Yes.deep)
    {
        auto filterContext = new XmlNodeFilterContext!S(document, XmlNodeType.element, localName, namespaceUri, context);
        if (deep)
            return XmlNodeList!S(this, XmlNodeListType.childNodesDeep, &filterContext.matchByLocalNameUri, filterContext);
        else
            return XmlNodeList!S(this, XmlNodeListType.childNodes, &filterContext.matchByLocalNameUri, filterContext);
    }

    /** Returns true if node is an ancestor of this node; false otherwise
        Params:
            node = a node to be checked
    */
    final bool isAncestorNode(XmlNode!S node) nothrow
    {
        auto n = parent;
        while (n !is null && n !is this)
        {
            if (n is node)
                return true;
            n = n.parent;
        }

        return false;
    }

    /** Returns true if this node accepts attribute (can have attribute); false otherwise
    */
    bool allowAttribute() const nothrow
    {
        return false;
    }

    /** Returns true if this node accepts a node except attribute (can have child); false otherwise
    */
    bool allowChild() const nothrow
    {
        return false;
    }

    /** Returns true if this node accepts a node with aNodeType except attribute (can have child);
        false otherwise
        Params:
            nodeType = a node type to be checked
    */
    bool allowChildType(XmlNodeType nodeType) nothrow
    {
        return false;
    }

    /** Inserts an attribute name to this node at the end
        If node already has the existing attribute name matched with name, it will return it;
        otherwise returns newly created attribute node
        If node does not accept attribute node, it will throw XmlInvalidOperationException exception
        Params:
            name = a name to be checked
        Returns:
            attribute node with name, name
    */
    final XmlAttribute!S appendAttribute(S name)
    {
        checkAttribute(null, "appendAttribute()");

        auto a = findAttribute(name);
        if (a is null)
            a = appendAttribute(selfOwnerDocument.createAttribute(name));

        return a;
    }

    /** Inserts a newChild to this node at the end and returns newChild
        If newChild is belong to a different parent node, it will be removed from that parent node before being addded
        If allowChild() or allowChildType() returns false, it will throw XmlInvalidOperationException exception
        Params:
            newChild = a child node to be appended
        Returns:
            newChild
    */
    final XmlNode!S appendChild(XmlNode!S newChild)
    {
        if (!isLoading())
            checkChild(newChild, "appendChild()");

        if (auto p = newChild.parent)
            p.removeChild(newChild);

        if (newChild.nodeType == XmlNodeType.documentFragment)
        {
            XmlNode!S next;
            XmlNode!S first = newChild.firstChild;
            XmlNode!S node = first;
            while (node !is null)
            {
                next = node.nextSibling;
                appendChild(newChild.removeChild(node));
                node = next;
            }
            return first;
        }

        debug(PhamXml) ++childVersion;

        newChild._parent = this;
        return _children.insertEnd(newChild);
    }

    /** Finds an attribute matched name with name and returns it;
        otherwise return null if no attribute with matched name found
        Params:
            name = a name to be checked
        Returns:
            Found attribute node
            Otherwise null
    */
    final XmlAttribute!S findAttribute(scope const(C)[] name) nothrow
    {
        const equalName = document.equalName;
        foreach (a; _attributes[])
        {
            if (equalName(a.name, name))
                return a;
        }
        return null;
    }

    /** Finds an attribute matched localName + namespaceUri with localName + namespaceUri and returns it;
        otherwise returns null if no attribute with matched localName + namespaceUri found
        Params:
            localName = a local-name to be checked
            namespaceUri = a name-space uri to be checked
        Returns:
            Found attribute node
            Otherwise null
    */
    final XmlAttribute!S findAttribute(scope const(C)[] localName, scope const(C)[] namespaceUri) nothrow
    {
        const equalName = document.equalName;
        foreach (a; _attributes[])
        {
            if (equalName(a.localName, localName) && equalName(a.namespaceUri, namespaceUri))
                return a;
        }
        return null;
    }

    /** Finds an attribute matched name with caseinsensitive "id" and returns it;
        otherwise returns null if no attribute with such name found
        Returns:
            Found attribute node
            Otherwise null
    */
    final XmlAttribute!S findAttributeById() nothrow
    {
        foreach (a; _attributes[])
        {
            if (equalCaseInsensitive!S(a.name, "id"))
                return a;
        }
        return null;
    }

    /** Finds an element matched name with name and returns it;
        otherwise return null if no element with matched name found
        Params:
            name = a name to be checked
            deep = need to search for element in all sub-nodes
        Returns:
            Found element node
            Otherwise null
    */
    final XmlElement!S findElement(scope const(C)[] name,
        Flag!"deep" deep = No.deep) nothrow
    {
        const equalName = document.equalName;

        // Prefer shallow level node before sub-nodes
        for (auto i = firstChild; i !is null; i = i.nextSibling)
        {
            if (i.nodeType == XmlNodeType.element && equalName(i.name, name))
                return cast(XmlElement!S)i;
        }

        if (deep)
        {
            for (auto i = firstChild; i !is null; i = i.nextSibling)
            {
                if (i.nodeType == XmlNodeType.element)
                {
                    if (auto found = i.findElement(name, deep))
                        return found;
                }
            }
        }

        return null;
    }

    /** Finds an element matched localName + namespaceUri with localName + namespaceUri and returns it;
        otherwise returns null if no element with matched localName + namespaceUri found
        Params:
            localName = a localName to be checked
            namespaceUri = a namespaceUri to be checked
            deep = need to search for element in all sub-nodes
        Returns:
            Found element node
            Otherwise null
    */
    final XmlElement!S findElement(scope const(C)[] localName, scope const(C)[] namespaceUri,
        Flag!"deep" deep = No.deep) nothrow
    {
        const equalName = document.equalName;

        // Prefer shallow level node before sub-nodes
        for (auto i = firstChild; i !is null; i = i.nextSibling)
        {
            if (i.nodeType == XmlNodeType.element &&
                equalName(i.localName, localName) &&
                equalName(i.namespaceUri, namespaceUri))
                return cast(XmlElement!S)i;
        }

        if (deep)
        {
            for (auto i = firstChild; i !is null; i = i.nextSibling)
            {
                if (i.nodeType == XmlNodeType.element)
                {
                    if (auto found = i.findElement(localName, namespaceUri, deep))
                        return found;
                }
            }
        }

        return null;
    }

    /** Finds an attribute matched name with name and returns its' value;
        otherwise return null if no attribute with matched name found
        Params:
            name = a named to be checked
        Returns:
            Its' found attribute value
            Otherwise null
    */
    final S getAttribute(scope const(C)[] name)
    {
        auto a = findAttribute(name);
        return a is null ? null : a.value;
    }

    /** Finds an attribute matched localName + namespaceUri with localName + namespaceUri and returns its' value;
        otherwise returns null if no attribute with matched localName + namespaceUri found
        Params:
            localName = a localName to be checked
            namespaceUri = a namespaceUri to be checked
        Returns:
            Its' found attribute value
            Otherwise null
    */
    final S getAttribute(scope const(C)[] localName, scope const(C)[] namespaceUri)
    {
        auto a = findAttribute(localName, namespaceUri);
        return a is null ? null : a.value;
    }

    /** Finds an attribute matched name with caseinsensitive "ID" and returns its' value;
        otherwise returns null if no attribute with such name found
    */
    final S getAttributeById()
    {
        auto a = findAttributeById();
        return a is null ? null : a.value;
    }

    /** Finds an element that have the mached attribute name id and returns it;
        otherwise return null if no element with such id named found
        Params:
            id = an search attribute value of named "id"
        Returns:
            Found element node
            Otherwise null
    */
    final XmlElement!S findElementById(scope const(C)[] id) nothrow
    {
        const equalName = document.equalName;

        // Prefer shallow level node before sub-nodes
        for (auto i = firstChild; i !is null; i = i.nextSibling)
        {
            if (i.nodeType == XmlNodeType.element && equalName(i.getAttributeById(), id))
                return cast(XmlElement!S)i;
        }

        for (auto i = firstChild; i !is null; i = i.nextSibling)
        {
            if (i.nodeType == XmlNodeType.element)
            {
                if (auto found = i.findElementById(id))
                    return found;
            }
        }

        return null;
    }

    /** Implement opIndex operator based on matched name
    */
    final XmlElement!S opIndex(scope const(C)[] name)
    {
        return findElement(name);
    }

    /** Implement opIndex operator based on matched localName + namespaceUri
    */
    final XmlElement!S opIndex(scope const(C)[] localName, scope const(C)[] namespaceUri)
    {
        return findElement(localName, namespaceUri);
    }

    /** Insert a child node, newChild, after anchor node, refChild and returns refChild
        If newChild is belong to a different parent node, it will be removed from that parent node before being inserted
        If allowChild() or allowChildType() returns false, it will throw XmlInvalidOperationException exception
        Params:
            newChild = a child node to be inserted
            refChild = a anchor node to as reference to position, newChild, after
        Returns:
            newChild
    */
    final XmlNode!S insertChildAfter(XmlNode!S newChild, XmlNode!S refChild)
    {
        checkChild(newChild, "insertChildAfter()");

        if (refChild is null)
            return appendChild(newChild);

        checkParent(refChild, true, "insertChildAfter()");

        if (auto n = newChild.parent)
            n.removeChild(newChild);

        if (newChild.nodeType == XmlNodeType.documentFragment)
        {
            XmlNode!S next;
            XmlNode!S first = newChild.firstChild;
            XmlNode!S node = first;
            while (node !is null)
            {
                next = node.nextSibling;
                insertChildAfter(newChild.removeChild(node), refChild);
                refChild = node;
                node = next;
            }
            return first;
        }

        debug(PhamXml) ++childVersion;

        newChild._parent = this;
        return _children.insertAfter(refChild, newChild);
    }

    /** Insert a child node, newChild, before anchor node, refChild and returns refChild
        If newChild is belong to a different parent node, it will be removed from that parent node before being inserted
        If allowChild() or allowChildType() returns false, it will throw XmlInvalidOperationException exception
        Params:
            newChild = a child node to be inserted
            refChild = a anchor node to as anchor position, newChild, before
        Returns:
            newChild
    */
    final XmlNode!S insertChildBefore(XmlNode!S newChild, XmlNode!S refChild)
    {
        checkChild(newChild, "insertChildBefore()");

        if (refChild is null)
            return appendChild(newChild);

        checkParent(refChild, true, "insertChildBefore()");

        if (auto n = newChild.parent)
            n.removeChild(newChild);

        if (newChild.nodeType == XmlNodeType.documentFragment)
        {
            XmlNode!S first = newChild.firstChild;
            XmlNode!S node = first;
            if (node !is null)
            {
                insertChildBefore(newChild.removeChild(node), refChild);
                // insert the rest of the children after this one.
                insertChildAfter(newChild, node);
            }
            return first;
        }

        debug(PhamXml) ++childVersion;

        newChild._parent = this;
        return _children.insertAfter(refChild._prev, newChild);
    }

    /** Returns string of xml structure of this node
        Params:
            prettyOutput = a boolean value to indicate if output xml should be nicely formated
        Returns:
            string of xml structure
    */
    final S outerXml(Flag!"prettyOutput" prettyOutput = No.prettyOutput)
    {
        auto buffer = selfOwnerDocument.acquireBuffer(nodeType);
        write(new XmlStringWriter!S(prettyOutput, buffer));
        return selfOwnerDocument.getAndReleaseBuffer(buffer);
    }

    /** Remove all its' child, sub-child and attribute nodes
    */
    final void removeAll()
    {
        removeChildNodes(Yes.deep);
        removeAttributes();
    }

    /** Remove an attribute, removedAttribute, from its attribute list
        If removedAttribute is not belonged to this node, it will throw XmlInvalidOperationException
        Params:
            removedAttribute = an attribute to be removed
        Returns:
            removedAttribute
    */
    final XmlAttribute!S removeAttribute(XmlAttribute!S removedAttribute)
    {
        checkParent(removedAttribute, false, "removeAttribute()");
        return removeAttributeImpl(removedAttribute);
    }

    /** Remove an attribute with name, name, from its' attribute list
        Params:
            name = an attribute name to be removed
        Returns:
            An attribute with name, name, if found
            Otherwise null
    */
    final XmlAttribute!S removeAttribute(scope const(C)[] name) nothrow
    {
        auto r = findAttribute(name);
        return r is null ? null : removeAttributeImpl(r);
    }

    /** Remove all its' attribute nodes
    */
    void removeAttributes()
    {
        if (_attributes.empty)
            return;

        debug(PhamXml) ++attrbVersion;

        while (!_attributes.empty)
        {
            auto last = _attributes.last;
            last._parent = null;
            _attributes.remove(last);
        }
    }

    /** Remove all its' child nodes or all its sub-nodes if deep is true
        Params:
            deep = true indicates if a removed node to recursively call removeChildNodes
    */
    void removeChildNodes(Flag!"deep" deep = No.deep)
    {
        if (_children.empty)
            return;

        debug(PhamXml) ++childVersion;

        while (!_children.empty)
        {
            auto last = _children.last;
            if (deep)
                last.removeChildNodes(Yes.deep);
            last._parent = null;
            _children.remove(last);
        }
    }

    /** Remove an child node, removedChild, from its' child node list
        If removedChild is not belonged to this node, it will throw XmlInvalidOperationException
        Params:
            removedChild = a child node to be removed
        Returns:
            removedChild
    */
    final XmlNode!S removeChild(XmlNode!S removedChild)
    {
        checkParent(removedChild, true, "removeChild()");

        debug(PhamXml) ++childVersion;

        removedChild._parent = null;
        return _children.remove(removedChild);
    }

    /** Replace an child node, oldChild, with newChild
        If newChild is belong to a different parent node, it will be removed from that parent node
        If oldChild is not belonged to this node, it will throw XmlInvalidOperationException
        If allowChild() or allowChildType() returns false, it will throw XmlInvalidOperationException exception
        Params:
            newChild = a child node to be placed into
            oldChild = a child node to be replaced
        Returns:
            oldChild
    */
    final XmlNode!S replaceChild(XmlNode!S newChild, XmlNode!S oldChild)
    {
        checkChild(newChild, "replaceChild()");
        checkParent(oldChild, true, "replaceChild()");

        debug(PhamXml) ++childVersion;

        auto pre = oldChild.previousSibling;

        oldChild._parent = null;
        _children.remove(oldChild);

        insertChildAfter(newChild, pre);

        return oldChild;
    }

    /** Find an attribute with name matched name and set its value to value
        If no attribute found, it will create a new attribute and set its' value
        If node does not accept attribute node, it will throw XmlInvalidOperationException exception
        Params:
            name = an attribute name to be added
            value = the value of the attribute node
        Returns:
            attribute node
    */
    final XmlAttribute!S setAttribute(S name, S value)
    {
        checkAttribute(null, "setAttribute()");
        return setAttributeImpl(name, value);
    }

    /** Find an attribute with localnamne + namespaceUri matched localName + namespaceUri and set its value to value
        If no attribute found, it will create a new attribute and set its' value
        If node does not accept attribute node, it will throw XmlInvalidOperationException exception
        Params:
            localName = an attribute localname to be added
            namespaceUri = an attribute namespaceUri to be added
            value = the value of the attribute node
        Returns:
            attribute node
    */
    final XmlAttribute!S setAttribute(S localName, S namespaceUri, S value)
    {
        checkAttribute(null, "setAttribute()");
        return setAttributeImpl(localName, namespaceUri, value);
    }

    /** Write out xml to writer according to its' structure
        Params:
            writer = output range to accept this node string xml structure
        Returns:
            writer
    */
    abstract XmlWriter!S write(XmlWriter!S writer);

    /** Returns its' attribute node list
    */
    @property XmlNodeList!S attributes()
    {
        return getAttributes(null);
    }

    /** Returns its' child node list
    */
    @property XmlNodeList!S childNodes()
    {
        return getChildNodes(null, No.deep);
    }

    /** Returns its' document node
    */
    @property XmlDocument!S document() nothrow pure
    {
        XmlDocument!S d;

        if (_parent !is null)
        {
            if (_parent.nodeType == XmlNodeType.document)
                return cast(XmlDocument!S)_parent;
            else
                d = _parent.document;
        }

        if (d is null)
        {
            d = ownerDocument;
            if (d is null)
                return selfOwnerDocument;
        }

        return d;
    }

    /** Returns its' first attribute node
        A null if node has no attribute
    */
    @property final XmlAttribute!S firstAttribute() nothrow
    {
        return _attributes.first;
    }

    /** Returns its' first child node. A null if node has no child
    */
    @property final XmlNode!S firstChild() nothrow
    {
        return _children.first;
    }

    /** Return true if a node has any attribute node, false otherwise
    */
    @property final bool hasAttributes() nothrow
    {
        return !_attributes.empty;
    }

    /** Return true if a node has any child node, false otherwise
    */
    @property final bool hasChildNodes() nothrow
    {
        return !_children.empty;
    }

    /** Returns true if a node has any value, false otherwise
        Params:
            checkContent = further check if value is empty or not
    */
    @property final bool hasValue(Flag!"checkContent" checkContent) const nothrow
    {
        switch (nodeType)
        {
            case XmlNodeType.attribute:
            case XmlNodeType.cdata:
            case XmlNodeType.comment:
            case XmlNodeType.processingInstruction:
            case XmlNodeType.text:
            case XmlNodeType.significantWhitespace:
            case XmlNodeType.whitespace:
            case XmlNodeType.declaration:
                return !checkContent || hasValueImpl();
            default:
                return hasValueImpl();
        }
    }

    /** Returns string of all its' child node text/value
    */
    @property S innerText()
    {
        auto first = firstChild;
        if (first is null)
            return null;
        else if (isOnlyNode(first) && first.isText)
            return first.innerText;
        else
        {
            auto buffer = selfOwnerDocument.acquireBuffer(nodeType);
            appendChildText(new XmlStringWriter!S(No.prettyOutput, buffer));
            return selfOwnerDocument.getAndReleaseBuffer(buffer);
        }
    }

    /** Setter of innerText
    */
    @property XmlNode!S innerText(S newValue)
    {
        auto first = firstChild;
        if (isOnlyNode(first) && first.nodeType == XmlNodeType.text)
            first.innerText = newValue;
        else
        {
            removeChildNodes(Yes.deep);
            appendChild(selfOwnerDocument.createText(newValue));
        }
        return this;
    }

    /** Return true if node is a namespace one, false otherwise
    */
    @property final bool isNamespaceNode() nothrow
    {
        return nodeType == XmlNodeType.attribute &&
            localName.length != 0 &&
            hasValueImpl() &&
            document.equalName(prefix, XmlConst!S.xmlns);
    }

    /** Returns true if aNode is the only child/attribute node (no sibling node),
        false otherwise
    */
    @property final bool isOnlyNode(XmlNode!S node) const nothrow
    {
        return node !is null &&
            node.previousSibling is null &&
            node.nextSibling is null;
    }

    /** Returns its' last attribute node. A null if node has no attribute
    */
    @property final XmlAttribute!S lastAttribute() nothrow
    {
        return _attributes.last;
    }

    /** Returns its' last child node. A null if node has no child
    */
    @property final XmlNode!S lastChild() nothrow
    {
        return _children.last;
    }

    /** Returns level within its' node hierarchy
    */
    @property size_t level() nothrow
    {
        return parent is null ? 0 : parent.level + 1;
    }

    /** Return node's localname if any, null otherwise
    */
    @property final S localName() nothrow
    {
        return _qualifiedName.localName;
    }

    /** Setter of localName
    */
    @property XmlNode!S localName(S newValue) nothrow
    {
        return this;
    }

    /** Return node's full name if any, null otherwise
    */
    @property final S name() nothrow
    {
        return _qualifiedName.name;
    }

    /** Setter of name
    */
    @property XmlNode!S name(S newValue) nothrow
    {
        return this;
    }

    /** Return node's namespceUri if any, null otherwise
    */
    @property final S namespaceUri() nothrow
    {
        return _qualifiedName.namespaceUri;
    }

    /** Setter of namespaceUri
    */
    @property XmlNode!S namespaceUri(S newValue) nothrow
    {
        return this;
    }

    /** Returns its' next sibling node. A null if node has no sibling
    */
    @property final XmlNode!S nextSibling() nothrow
    {
        if (parent is null)
            return _next;

        auto last = nodeType == XmlNodeType.attribute ? parent.lastAttribute : parent.lastChild;
        return this is last ? null : _next;
    }

    /** Returns an enum of XmlNodeType of its' presentation
    */
    @property abstract XmlNodeType nodeType() const nothrow pure;

    /** Return node's document owner if any, null otherwise
    */
    @property final XmlDocument!S ownerDocument() nothrow pure
    {
        return _ownerDocument;
    }

    /** Returns its' parent node if any, null otherwise
    */
    @property final XmlNode!S parent() nothrow pure
    {
        return _parent;
    }

    version(none)
    @property final ptrdiff_t indexOf() nothrow
    {
        if (auto p = parentNode())
        {
            ptrdiff_t result = 0;
            if (nodeType == XmlNodeType.attribute)
            {
                auto e = p.firstAttribute;
                while (e !is null)
                {
                    if (e is this)
                        return result;
                    ++result;
                    e = e.nextSibling;
                }
            }
            else
            {
                auto e = p.firstChild;
                while (e !is null)
                {
                    if (e is this)
                        return result;
                    ++result;
                    e = e.nextSibling;
                }
            }
        }

        return -1;
    }

    /** Returns prefix of its' qualified name if any, null otherwise
    */
    @property final S prefix() nothrow
    {
        return _qualifiedName.prefix;
    }

    /** Setter of prefix
    */
    @property XmlNode!S prefix(S newPrefix) nothrow
    {
        return this;
    }

    /** Returns its' previous sibling node. null if node has no sibling
    */
    @property final XmlNode!S previousSibling() nothrow
    {
        if (parent is null)
            return _prev;

        auto first = nodeType == XmlNodeType.attribute ? parent.firstAttribute : parent.firstChild;
        return this is first ? null : _prev;
    }

    /**
     * Return node's value if any, null otherwise
     */
    @property S value() nothrow
    {
        return null;
    }

    /**
     * Setter of value. Do nothing if node does not accept value
     */
    @property XmlNode!S value(S newValue) nothrow
    {
        return this;
    }

package:
    final XmlAttribute!S appendAttribute(XmlAttribute!S newAttribute) nothrow
    in
    {
        assert(!isLoading() || isAllowAttribute(newAttribute) == 0);
    }
    do
    {
        if (!isLoading())
        {
            if (auto p = newAttribute.parent)
                p.removeAttributeImpl(newAttribute);
        }

        debug(PhamXml) ++attrbVersion;

        newAttribute._parent = this;
        return _attributes.insertEnd(newAttribute);
    }

    final void checkAttribute(XmlNode!S attribute, string op)
    {
        switch (isAllowAttribute(attribute))
        {
            case 1: throw new XmlInvalidOperationException(XmlMessage.eInvalidOpDelegate, shortClassName(this), op);
            case 2: throw new XmlInvalidOperationException(XmlMessage.eNotAllowAppendDifDoc, "attribute");
            case 3: throw new XmlInvalidOperationException(XmlMessage.eAttributeDuplicated, attribute.name);
            default: break;
        }
    }

    final void checkChild(XmlNode!S child, string op)
    {
        if (!allowChild())
            throw new XmlInvalidOperationException(XmlMessage.eInvalidOpDelegate, shortClassName(this), op);

        if (child !is null)
        {
            if (!allowChildType(child.nodeType))
                throw new XmlInvalidOperationException(XmlMessage.eNotAllowChild, shortClassName(this), op,
                    name, nodeType, child.name, child.nodeType);

            if (child.ownerDocument !is null && child.ownerDocument !is selfOwnerDocument)
                throw new XmlInvalidOperationException(XmlMessage.eNotAllowAppendDifDoc, "child");

            if (child is this || isAncestorNode(child))
                throw new XmlInvalidOperationException(XmlMessage.eNotAllowAppendSelf);
        }
    }

    final int isAllowAttribute(XmlNode!S attribute) nothrow
    {
        if (!allowAttribute())
            return 1;

        if (attribute !is null)
        {
            if (attribute.ownerDocument !is null && attribute.ownerDocument !is selfOwnerDocument)
                return 2;

            if (findAttribute(attribute.name) !is null)
                return 3;
        }

        return 0;
    }

protected:
    final void appendChildText(XmlStringWriter!S writer)
    {
        for (XmlNode!S i = firstChild; i !is null; i = i.nextSibling)
        {
            if (!i.hasChildNodes)
            {
                switch (i.nodeType)
                {
                    case XmlNodeType.cdata:
                    case XmlNodeType.significantWhitespace:
                    case XmlNodeType.text:
                    case XmlNodeType.whitespace:
                        writer.put(i.innerText);
                        break;
                    default:
                        break;
                }
            }
            else
                i.appendChildText(writer);
        }
    }

    final void checkParent(XmlNode!S node, bool child, string op)
    {
        if (node._parent !is this)
            throw new XmlInvalidOperationException(XmlMessage.eInvalidOpFromWrongParent, shortClassName(this), op);

        if (child && node.nodeType == XmlNodeType.attribute)
            throw new XmlInvalidOperationException(XmlMessage.eInvalidOpDelegate, shortClassName(this), op);
    }

    final XmlNode!S findChild(XmlNodeType nodeType) nothrow
    {
        for (XmlNode!S i = firstChild; i !is null; i = i.nextSibling)
        {
            if (i.nodeType == nodeType)
                return i;
        }
        return null;
    }

    bool hasValueImpl() const nothrow pure
    {
        return false;
    }

    bool isLoading() nothrow pure
    {
        return selfOwnerDocument().isLoading();
    }

    /**
     * Returns true if this node is a Text type node
     * cdata, comment, significantWhitespace, text & whitespace
     */
    bool isText() const nothrow pure
    {
        return false;
    }

    final XmlAttribute!S removeAttributeImpl(XmlAttribute!S removedAttribute) nothrow
    {
        debug(PhamXml) ++attrbVersion;

        removedAttribute._parent = null;
        return _attributes.remove(removedAttribute);
    }

    XmlDocument!S selfOwnerDocument() nothrow pure
    {
        return _ownerDocument;
    }

    final XmlAttribute!S setAttributeImpl(S name, S value) nothrow
    {
        auto a = findAttribute(name);
        if (a is null)
            a = appendAttribute(selfOwnerDocument.createAttribute(name));
        a.value = value;
        return a;
    }

    final XmlAttribute!S setAttributeImpl(S localName, S namespaceUri, S value) nothrow
    {
        auto a = findAttribute(localName, namespaceUri);
        if (a is null)
            a = appendAttribute(selfOwnerDocument.createAttribute("", localName, namespaceUri));
        a.value = value;
        return a;
    }

    final XmlWriter!S writeAttributes(XmlWriter!S writer)
    {
        assert(hasAttributes == true);

        XmlNode!S attrb = firstAttribute;
        attrb.write(writer);

        attrb = attrb.nextSibling;
        while (attrb !is null)
        {
            writer.put(' ');
            attrb.write(writer);
            attrb = attrb.nextSibling;
        }

        return writer;
    }

    final XmlWriter!S writeChildren(XmlWriter!S writer)
    {
        assert(hasChildNodes == true);

        const canIndent = nodeType != XmlNodeType.document && nodeType != XmlNodeType.documentFragment;
        if (canIndent)
            writer.incNodeLevel();

        auto node = firstChild;
        while (node !is null)
        {
            node.write(writer);
            node = node.nextSibling;
        }

        if (canIndent)
            writer.decNodeLevel();

        return writer;
    }

public:
    mixin DLinkTypes!(XmlNode!S) DLinkXmlNodeTypes;
    mixin DLinkTypes!(XmlAttribute!S) DLinkXmlAttributeTypes;

protected:
    XmlDocument!S _ownerDocument;
    DLinkXmlAttributeTypes.DLinkList _attributes;
    DLinkXmlNodeTypes.DLinkList _children;
    XmlNode!S _parent;
    XmlName!S _qualifiedName;
    debug(PhamXml)
    {
        size_t attrbVersion;
        size_t childVersion;
    }

private:
    XmlNode!S _next;
    XmlNode!S _prev;
}

/**
 * A struct type for holding various xml node objects
 * It implements range base api
 */
struct XmlNodeList(S = string)
if (isXmlString!S)
{
@safe:

public:
    alias C = XmlChar!S;
    alias This = typeof(this);
    alias XmlNodeListFilterEvent = bool delegate(Object context, XmlNode!S node);

public:
    this(this) nothrow
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "()");

        if (_listType == XmlNodeListType.childNodesDeep)
            _walkNodes = _walkNodes.dup;
    }

    /**
     * Create a XmlNodeList with listType is XmlNodeListType.flat
     */
    this(Object context) nothrow
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "()");

        this._orgParent = null;
        this._listType = XmlNodeListType.flat;
        this._onFilter = null;
        this._filterContext = cast(XmlNodeFilterContext!S)context;
        this._context = this._filterContext !is null ? this._filterContext.context : context;

        reset2();
    }

    /**
     * Create a XmlNodeList with listType is not XmlNodeListType.flat
     */
    this(XmlNode!S parent, XmlNodeListType listType, XmlNodeListFilterEvent onFilter, Object context)
    in
    {
        assert(parent !is null);
        assert(listType != XmlNodeListType.flat);
    }
    do
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "()");

        if (listType == XmlNodeListType.flat)
            throw new XmlInvalidOperationException(XmlMessage.eInvalidOpDelegate, "XmlNodeList", "this(listType = XmlNodeListType.flat)");

        this._orgParent = parent;
        this._listType = listType;
        this._onFilter = onFilter;
        this._filterContext = cast(XmlNodeFilterContext!S)context;
        this._context = this._filterContext !is null ? this._filterContext.context : context;

        if (listType == XmlNodeListType.childNodesDeep)
            _walkNodes.reserve(defaultXmlLevels);

        reset();
    }

    /**
     * Notes:
     *   this slow, O(n), access, better use front & popFront
     */
    // Not implement because it is not obviously slow, use item() instead
    version(none)
    XmlNode!S opIndex(size_t index)
    {
        return item(index);
    }

    XmlNode!S opIndex(scope const(C)[] name)
    {
        return item(name);
    }

    /**
     * Returns the last item in the list
     * Returns:
     *   xml node object
     */
    XmlNode!S back()
    in
    {
        assert(!empty);
    }
    do
    {
        return item(length() - 1);
    }

    /**
     * Insert a xml node, node, to the end
     * Valid only if listType is XmlNodeListType.flat
     * Params:
     *   node = a xml node to be inserted
     * Returns:
     *   node if allowed, otherwise null
     */
    XmlNode!S insertBack(XmlNode!S node) nothrow
    in
    {
        assert(_listType == XmlNodeListType.flat);
    }
    do
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "()");

        if (_listType == XmlNodeListType.flat)
        {
            _flatList ~= node;
            return node;
        }

        return null;
    }

    /**
     * Returns the item in the list at index, index
     * Params:
     *   index = index where a xml node to be returned
     * Returns:
     *   xml node at index if existed, otherwise null
     * Notes:
     *   this slow, O(n), access, better use front & popFront
     */
    pragma(inline, true)
    XmlNode!S item(size_t index)
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "(index=", index, ")");

        return empty ? null : _doGetIndexedItem(this, index);
    }

    pragma(inline, true)
    XmlNode!S item(scope const(C)[] name)
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "(name=", name, ")");

        return empty ? null : _doGetNamedItem(this, name);
    }

    /**
     * Returns the count of xml nodes
     * It can be expensive operation if listType != XmlNodeListType.flat
     * Returns:
     *   count of xml nodes
     */
    size_t length()
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "()");

        if (empty)
            return 0;

        if (_listType == XmlNodeListType.flat)
            return _flatList.length - _currentOffset;

        debug(PhamXml) checkVersionChanged();

        if (_length == unknownLength)
        {
            auto restore = this;

            size_t tempLength = 0;
            while (_current !is null)
            {
                tempLength++;
                popFront();
            }

            this = restore; // Restore before setting _length
            _length = tempLength;
        }

        return _length;
    }

    /**
     * An input range operation by moving front to the next node
     * and returns the current node object
     * Returns:
     *   Current front node before the call
     */
    XmlNode!S moveFront()
    in
    {
        assert(!empty);
    }
    do
    {
        auto f = front;
        popFront();
        return f;
    }

    /**
     * An input range operation by moving front to the next node
     */
    pragma(inline, true)
    void popFront()
    in
    {
        assert(!empty);
    }
    do
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "()");

        _doPopFront(this);
    }

    /**
     * Returns the index of node in this node-list
     * if node is not in the list, returns -1
     * Based 1 value
     * Params:
     *   node = a xml node to be calculated
     * Returns:
     *   A index of node in the list if found, otherwise -1
     */
    ptrdiff_t indexOf(XmlNode!S node)
    {
        foreach (i; 0..length())
        {
            if (node is item(i))
                return i;
        }
        return -1;
    }

    void removeAll()
    {
        final switch (_listType)
        {
            case XmlNodeListType.attributes:
                _orgParent.removeAttributes();
                break;
            case XmlNodeListType.childNodes:
                _orgParent.removeChildNodes(No.deep);
                break;
            case XmlNodeListType.childNodesDeep:
                _orgParent.removeChildNodes(Yes.deep);
                break;
            case XmlNodeListType.flat:
                _flatList.length = 0;
                break;
        }

        reset();
    }

    void reset()
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "()");

        reset2();

        debug(PhamXml)
        {
            if (_listType == XmlNodeListType.Attributes)
                _parentVersion = getVersionAttrb();
            else
                _parentVersion = getVersionChild();
        }

        if (canDoFilter())
            checkFilter(&popFront);

        _length = _current is null ? 0 : unknownLength;
    }

    typeof(this) save()
    {
        return this;
    }

    @property Object context() nothrow pure
    {
        return _context;
    }

    /**
     * An input range operation to return if there is any node left in this instance
     */
    pragma(inline, true)
    @property bool empty() const nothrow pure
    {
        return _listType == XmlNodeListType.flat
            ? _currentOffset >= _flatList.length
            : _current is null;
    }

    /**
     * An input range operation to return current node if any
     */
    pragma(inline, true)
    @property XmlNode!S front() nothrow pure
    in
    {
        assert(!empty);
    }
    do
    {
        return _listType == XmlNodeListType.flat
            ? _flatList[_currentOffset]
            : _current;
    }

    pragma(inline, true)
    @property XmlNodeListType listType() const nothrow pure
    {
        return _listType;
    }

    pragma(inline, true)
    @property XmlNode!S parent() nothrow pure
    {
        return _orgParent;
    }

private:
    void checkFilter(void delegate() @safe advance)
    in
    {
        assert(_listType != XmlNodeListType.flat);
    }
    do
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "()");

        _inFilter++;
        scope (exit)
            _inFilter--;

        while (_current !is null && !_onFilter(_context, _current))
            advance();
    }

    static void checkFilter(ref This list, void function(ref This) @safe advance)
    in
    {
        assert(list._listType != XmlNodeListType.flat);
    }
    do
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "()");

        list._inFilter++;
        scope (exit)
            list._inFilter--;

        while (list._current !is null && !list._onFilter(list._context, list._current))
            advance(list);
    }

    pragma(inline, true)
    bool canDoFilter() const nothrow pure
    {
        return _inFilter == 0 && _current !is null && _onFilter !is null;
    }

    static XmlNode!S getIndexedItemDeep(ref This list, size_t index)
    in
    {
        assert(list._listType == XmlNodeListType.childNodesDeep);
    }
    do
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "()");
        debug(PhamXml) list.checkVersionChanged();

        if (index == 0 || list._current is null)
            return list._current;

        auto restore = list;
        scope (exit)
            list = restore;

        while (index != 0 && list._current !is null)
        {
            popFrontDeep(list);
            index--;
        }

        return index == 0 ? list._current : null;
    }

    static XmlNode!S getIndexedItemFlat(ref This list, size_t index)
    in
    {
        assert(list._listType == XmlNodeListType.flat);
    }
    do
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "(index=", index, ")");

        const i = index + list._currentOffset;
        return i < list._flatList.length ? list._flatList[i] : null;
    }

    static XmlNode!S getIndexedItemSibling(ref This list, size_t index)
    in
    {
        assert(list._listType != XmlNodeListType.flat && list._listType != XmlNodeListType.childNodesDeep);
    }
    do
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "(index=", index, ")");
        debug(PhamXml) list.checkVersionChanged();

        if (index == 0 || list._current is null)
            return list._current;

        auto restore = list;
        scope (exit)
            list = restore;

        while (index != 0 && list._current !is null)
        {
            popFrontSibling(list);
            index--;
        }

        return index == 0 ? list._current : null;
    }

    static XmlNode!S getNamedItemDeep(ref This list, scope const(C)[] name)
    in
    {
        assert(list._listType == XmlNodeListType.childNodesDeep);
    }
    do
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "(name=", name, ")");
        debug(PhamXml) list.checkVersionChanged();

        if (list._current is null)
            return null;

        auto restore = list;
        scope (exit)
            list = restore;

        const equalName = list._filterContext !is null
            ? list._filterContext.equalName
            : list._current.document.equalName;
        while (list._current !is null)
        {
            auto nodeName = list._current.name;
            if (nodeName.length != 0 && equalName(nodeName, name))
                return list._current;
            popFrontDeep(list);
        }

        return null;
    }

    static XmlNode!S getNamedItemFlat(ref This list, scope const(C)[] name)
    in
    {
        assert(list._listType == XmlNodeListType.flat);
    }
    do
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "(name=", name, ")");

        if (list._currentOffset >= list._flatList.length)
            return null;

        const equalName = list._filterContext !is null
            ? list._filterContext.equalName
            : list._flatList[list._currentOffset].document.equalName;
        foreach (i; list._currentOffset..list._flatList.length)
        {
            auto nodeName = list._flatList[i].name;
            if (nodeName.length != 0 && equalName(nodeName, name))
                return list._flatList[i];
        }

        return null;
    }

    static XmlNode!S getNamedItemSibling(ref This list, scope const(C)[] name)
    in
    {
        assert(list._listType != XmlNodeListType.flat && list._listType != XmlNodeListType.childNodesDeep);
    }
    do
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "(name=", name, ")");
        debug(PhamXml) list.checkVersionChanged();

        if (list._current is null)
            return null;

        auto restore = list;
        scope (exit)
            list = restore;

        const equalName = list._filterContext !is null
            ? list._filterContext.equalName
            : list._current.document.equalName;
        while (list._current !is null)
        {
            auto nodeName = list._current.name;
            if (nodeName.length != 0 && equalName(nodeName, name))
                return list._current;
            popFrontSibling(list);
        }

        return null;
    }

    static void popFrontDeep(ref This list)
    in
    {
        assert(list._listType == XmlNodeListType.childNodesDeep);
        assert(list._current !is null);
    }
    do
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "(list._current.name=", list._current.name, ")");
        debug(PhamXml) list.checkVersionChanged();

        popFrontDeepImpl(list);
        if (list.canDoFilter())
            checkFilter(list, &popFrontDeepImpl);
        list.popFrontLength();
    }

    static void popFrontDeepImpl(ref This list)
    in
    {
        assert(list._listType == XmlNodeListType.childNodesDeep);
        assert(list._current !is null);
    }
    do
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "(list._parent.name=", list._parent.name, ")");
        debug(PhamXml) list.checkVersionChanged();

        if (list._current.hasChildNodes)
        {
            if (list._current.nextSibling !is null)
            {
                debug(debug_pham_xml_xml_dom) debug writeln("\t", "list._parent.name=", list._parent.name);

                list._walkNodes ~= WalkNode(list._parent, list._current.nextSibling);
            }

            list._parent = list._current;
            list._current = list._current.firstChild;
            debug(PhamXml) list._parentVersion = list.getVersionChild();
        }
        else
        {
            list._current = list._current.nextSibling;
            while (list._current is null && list._walkNodes.length != 0)
            {
                const lastIndex = list._walkNodes.length - 1;
                list._parent = list._walkNodes[lastIndex].parent;
                list._current = list._walkNodes[lastIndex].next;
                debug(PhamXml) list._parentVersion = list._walkNodes[lastIndex].parentVersion;
                list._walkNodes.length = lastIndex;
            }
        }
    }

    static void popFrontFlat(ref This list)
    in
    {
        assert(list._listType == XmlNodeListType.flat);
    }
    do
    {
        list._currentOffset++;
    }

    pragma(inline, true)
    void popFrontLength()
    {
        if (_current is null)
            _length = 0;
        else if (_length != unknownLength)
        {
            assert(_length != 0);
            _length--;
        }
    }

    static void popFrontSibling(ref This list)
    in
    {
        assert(list._listType != XmlNodeListType.flat && list._listType != XmlNodeListType.childNodesDeep);
        assert(list._current !is null);
    }
    do
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "()");
        debug(PhamXml) list.checkVersionChanged();

        popFrontSiblingImpl(list);
        if (list.canDoFilter())
            checkFilter(list, &popFrontSiblingImpl);
        list.popFrontLength();
    }

    static void popFrontSiblingImpl(ref This list)
    in
    {
        assert(list._listType != XmlNodeListType.flat && list._listType != XmlNodeListType.childNodesDeep);
        assert(list._current !is null);
    }
    do
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "()");
        debug(PhamXml) list.checkVersionChanged();

        list._current = list._current.nextSibling;
    }

    void reset2() nothrow
    {
        debug(debug_pham_xml_xml_dom) debug writeln(__FUNCTION__, "()");

        _currentOffset = 0;
        _length = unknownLength;
        _parent = _orgParent;
        final switch (_listType)
        {
            case XmlNodeListType.attributes:
                _current = _parent.firstAttribute;
                _doGetIndexedItem = &getIndexedItemSibling;
                _doGetNamedItem = &getNamedItemSibling;
                _doPopFront = &popFrontSibling;
                break;
            case XmlNodeListType.childNodes:
                _current = _parent.firstChild;
                _doGetIndexedItem = &getIndexedItemSibling;
                _doGetNamedItem = &getNamedItemSibling;
                _doPopFront = &popFrontSibling;
                break;
            case XmlNodeListType.childNodesDeep:
                _current = _parent.firstChild;
                _doGetIndexedItem = &getIndexedItemDeep;
                _doGetNamedItem = &getNamedItemDeep;
                _doPopFront = &popFrontDeep;
                break;
            case XmlNodeListType.flat:
                _current = null;
                _doGetIndexedItem = &getIndexedItemFlat;
                _doGetNamedItem = &getNamedItemFlat;
                _doPopFront = &popFrontFlat;
                break;
        }
    }

    debug(PhamXml)
    {
        pragma (inline, true)
        size_t getVersionAttrb() const nothrow
        {
            return _parent.attrbVersion;
        }

        pragma (inline, true)
        size_t getVersionChild() const nothrow
        {
            return _parent.childVersion;
        }

        void checkVersionChangedAttrb() const
        {
            if (_parentVersion != getVersionAttrb())
                throw new XmlException(Message.EAttributeListChanged);
        }

        void checkVersionChangedChild() const
        {
            if (_parentVersion != getVersionChild())
                throw new XmlException(Message.EChildListChanged);
        }

        pragma (inline, true)
        void checkVersionChanged() const
        {
            if (_listType == XmlNodeListType.Attributes)
                checkVersionChangedAttrb();
            else
                checkVersionChangedChild();
        }
    }

private:
    static struct WalkNode
    {
        XmlNode!S parent, next;
        debug(PhamXml) size_t parentVersion;

        this(XmlNode!S parent, XmlNode!S next)
        {
            this.parent = parent;
            this.next = next;
            debug(PhamXml) this.parentVersion = parent.childVersion;
        }
    }

    alias DoGetIndexedItem = XmlNode!S function(ref This, size_t) @safe;
    alias DoGetNamedItem = XmlNode!S function(ref This, scope const(C)[]) @safe;
    alias DoPopFront = void function(ref This) @safe;
    enum unknownLength = size_t.max;

    DoGetIndexedItem _doGetIndexedItem;
    DoGetNamedItem _doGetNamedItem;
    DoPopFront _doPopFront;
    Object _context;
    XmlNodeFilterContext!S _filterContext;
    XmlNode!S _orgParent, _parent, _current;
    XmlNode!S[] _flatList;
    WalkNode[] _walkNodes;
    XmlNodeListFilterEvent _onFilter;
    size_t _currentOffset;
    size_t _length;
    debug(PhamXml) size_t _parentVersion;
    int _inFilter;
    XmlNodeListType _listType;
}

/** A xml attribute node object
*/
class XmlAttribute(S = string) : XmlNode!S
{
@safe:

public:
    this(XmlDocument!S ownerDocument, XmlName!S name) nothrow
    /* TODO Crash DMD compiler
    in
    {
        if (!ownerDocument.isLoading())
        {
            assert(isName!(S, Yes.AllowEmpty)(name.prefix));
            assert(isName!(S, No.AllowEmpty)(name.localName));
        }
    }
    do
    */
    {
        this._ownerDocument = ownerDocument;
        this._qualifiedName = name;
    }

    this(XmlDocument!S ownerDocument, XmlName!S name, S text) nothrow
    {
        this(ownerDocument, name);
        this._text = XmlString!S(text);
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        writer.putAttribute(name, ownerDocument.getEncodedText(_text));
        return writer;
    }

    @property final override S innerText()
    {
        return value;
    }

    @property final override XmlNode!S innerText(S newValue)
    {
        return value(newValue);
    }

    @property final override size_t level() nothrow
    {
        return parent is null ? 0 : parent.level;
    }

    alias localName = typeof(super).localName;

    @property final override XmlNode!S localName(S newValue) nothrow
    {
        _qualifiedName = ownerDocument.createName(prefix, newValue, namespaceUri);
        return this;
    }

    alias name = typeof(super).name;

    @property final override XmlNode!S name(S newValue) nothrow
    {
        _qualifiedName = ownerDocument.createName(newValue);
        return this;
    }

    alias namespaceUri = typeof(super).namespaceUri;

    @property final override XmlNode!S namespaceUri(S newValue) nothrow
    {
        _qualifiedName = ownerDocument.createName(prefix, localName, newValue);
        return this;
    }

    @property final override XmlNodeType nodeType() const nothrow pure
    {
        return XmlNodeType.attribute;
    }

    alias prefix = typeof(super).prefix;

    @property final override XmlNode!S prefix(S newValue) nothrow
    {
        _qualifiedName = ownerDocument.createName(newValue, localName, namespaceUri);
        return this;
    }

    @property final override S value() nothrow
    {
        return ownerDocument.getDecodedText(_text);
    }

    @property final override XmlNode!S value(S newValue) nothrow
    {
        _text = newValue;
        return this;
    }

package:
    this(XmlDocument!S ownerDocument, XmlName!S name, XmlString!S text) nothrow
    /* TODO Crash DMD compiler
    in
    {
        if (!ownerDocument.isLoading())
        {
            assert(isName!(S, Yes.AllowEmpty)(name.prefix));
            assert(isName!(S, No.AllowEmpty)(name.localName));
        }
    }
    do
    */
    {
        this._ownerDocument = ownerDocument;
        this._qualifiedName = name;
        this._text = text;
    }

protected:
    final override bool hasValueImpl() const nothrow pure
    {
        return _text.length != 0;
    }

protected:
    XmlString!S _text;
}

/** A xml cdata node object
*/
class XmlCData(S = string) : XmlCharacterDataCustom!S
{
@safe:

public:
    this(XmlDocument!S ownerDocument, S data) nothrow @trusted
    {
        super(ownerDocument, XmlString!S(data, XmlEncodeMode.none));
        this._qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        writer.putCData(_text.value);
        return writer;
    }

    @property final override XmlNodeType nodeType() const nothrow pure
    {
        return XmlNodeType.cdata;
    }

protected:
    static XmlName!S createDefaultQualifiedName() nothrow pure
    {
        return new XmlName!S(XmlConst!S.CDataTagName);
    }

private:
    __gshared static XmlName!S _defaultQualifiedName;
}

/** A xml comment node object
*/
class XmlComment(S = string) : XmlCharacterDataCustom!S
{
@safe:

public:
    this(XmlDocument!S ownerDocument, S text) nothrow @trusted
    {
        super(ownerDocument, text);
        this._qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        writer.putComment(ownerDocument.getEncodedText(_text));
        return writer;
    }

    @property final override XmlNodeType nodeType() const nothrow pure
    {
        return XmlNodeType.comment;
    }

package:
    this(XmlDocument!S ownerDocument, XmlString!S text) @trusted
    {
        super(ownerDocument, text);
        this._qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
    }

protected:
    static XmlName!S createDefaultQualifiedName() nothrow pure
    {
        return new XmlName!S(XmlConst!S.commentTagName);
    }

private:
    __gshared static XmlName!S _defaultQualifiedName;
}

/** A xml declaration node object
*/
class XmlDeclaration(S = string) : XmlNode!S
{
@safe:

public:
    this(XmlDocument!S ownerDocument) nothrow @trusted
    {
        this._ownerDocument = ownerDocument;
        this._qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
    }

    this(XmlDocument!S ownerDocument, S versionStr, S encoding, bool standalone) nothrow
    in
    {
        assert(ownerDocument.isLoading() || isVersionStr!(S, Yes.AllowEmpty)(versionStr));
    }
    do
    {
        this(ownerDocument);
        this.versionStr = versionStr;
        this.encoding = encoding;
        this.standalone = standalone;
    }

    final override bool allowAttribute() const nothrow
    {
        return true;
    }

    final void setDefaults()
    {
        if (versionStr.length == 0)
            versionStr = "1.0";

        if (encoding.length == 0)
            encoding = "utf-8";
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        //Flag!"hasAttribute";
        const a = hasAttributes ? Yes.hasAttribute : No.hasAttribute;

        writer.putElementNameBegin("?xml", a);
        if (a)
            writeAttributes(writer);
        writer.putElementNameEnd("?xml", No.hasChild);
        return writer;
    }

    @property final S encoding() nothrow
    {
        return getAttribute(XmlConst!S.declarationEncodingName);
    }

    @property final typeof(this) encoding(S newValue) nothrow
    {
        if (newValue.length == 0)
            removeAttribute(XmlConst!S.declarationEncodingName);
        else
            setAttributeImpl(XmlConst!S.declarationEncodingName, newValue);
        buildText();
        return this;
    }

    @property final override S innerText()
    {
        return _innerText;
    }

    @property final override XmlNode!S innerText(S newValue)
    {
        breakText(newValue);
        return this;
    }

    @property final override XmlNodeType nodeType() const nothrow pure
    {
        return XmlNodeType.declaration;
    }

    @property final S standalone() nothrow
    {
        return getAttribute(XmlConst!S.declarationStandaloneName);
    }

    @property final typeof(this) standalone(bool newValue) nothrow
    {
        auto newValueText = newValue ? XmlConst!S.yes : XmlConst!S.no;
        setAttributeImpl(XmlConst!S.declarationStandaloneName, newValueText);
        buildText();
        return this;
    }

    @property final override S value() nothrow
    {
        return _innerText;
    }

    @property final override XmlNode!S value(S newValue) nothrow
    {
        breakText(newValue);
        return this;
    }

    @property final S versionStr() nothrow
    {
        return getAttribute(XmlConst!S.declarationVersionName);
    }

    @property final typeof(this) versionStr(S newValue) nothrow
    {
        if (newValue.length == 0)
            removeAttribute(XmlConst!S.declarationVersionName);
        else
            setAttributeImpl(XmlConst!S.declarationVersionName, newValue);
        buildText();
        return this;
    }

protected:
    final void breakText(S s) nothrow
    {
        scope (failure) assert(0, "Assume nothrow failed");

        S[] t = s.split();
        foreach (e; t)
        {
            S name, value;
            splitNameValueD!S(e, '=', name, value);

            const equalName = document.equalName;
            if (equalCaseInsensitive!S(name, XmlConst!S.declarationVersionName))
                versionStr = value;
            else if (equalCaseInsensitive!S(name, XmlConst!S.declarationEncodingName))
                encoding = value;
            else if (equalCaseInsensitive!S(name, XmlConst!S.declarationStandaloneName))
            {
                assert(isStandalone(value));
                standalone = value == XmlConst!S.yes;
            }
            else
            {
                //throw new XmlException(XmlMessage.eInvalidName, name);
                assert(0);
            }
        }
    }

    final S buildText() nothrow
    {
        scope (failure) assert(0, "Assume nothrow failed");

        auto buffer = selfOwnerDocument.acquireBuffer(nodeType);
        scope (exit)
            selfOwnerDocument.releaseBuffer(buffer);

        auto writer = new XmlStringWriter!S(No.prettyOutput, buffer);

        const(C)[] s;

        s = versionStr;
        if (s.length)
        {
            if (buffer.length)
                writer.put(' ');
            writer.putAttribute(XmlConst!S.declarationVersionName, s);
        }

        s = encoding;
        if (s.length)
        {
            if (buffer.length)
                writer.put(' ');
            writer.putAttribute(XmlConst!S.declarationEncodingName, s);
        }

        s = standalone;
        if (s.length)
        {
            if (buffer.length)
                writer.put(' ');
            writer.putAttribute(XmlConst!S.declarationStandaloneName, s);
        }

        _innerText = buffer.valueAndClear();

        return _innerText;
    }

    version(none)
    final void checkStandalone(S s)
    {
        if (!isStandalone(s))
            throw new XmlException(XmlMessage.eInvalidTypeValueOf2,
                XmlConst!string.declarationStandaloneName, XmlConst!string.yes, XmlConst!string.no, s);
    }

    version(none)
    final void checkVersion(scope const(C)[] s) // rule 26
    {
        if (!isVersionStr!(S, Yes.AllowEmpty)(s))
            throw new XmlException(XmlMessage.eInvalidVersionStr, s);
    }

    static XmlName!S createDefaultQualifiedName() nothrow pure
    {
        return new XmlName!S(XmlConst!S.declarationTagName);
    }

    final override bool hasValueImpl() const nothrow pure
    {
        return _innerText.length != 0;
    }

    static bool isStandalone(S s) nothrow pure
    {
        return s.length == 0 || s == XmlConst!S.yes || s == XmlConst!S.no;
    }

protected:
    S _innerText;

private:
    __gshared static XmlName!S _defaultQualifiedName;
}

/** A xml document node object
*/
class XmlDocument(S = string) : XmlNode!S
{
@safe:

public:
    alias EqualName = bool function(scope const(C)[] s1, scope const(C)[] s2) nothrow pure @safe;

public:
    /** A function pointer that is used for name comparision. This is allowed to be used
    to compare name without case-sensitive.
    Default is case-sensitive comparision
    */
    EqualName equalName;

    /** Default namespace value of this document
    */
    S defaultUri;

    /** Controls whether to use symbol table for node name to conserve memory usage
    */
    bool useSymbolTable;

public:
    this() @trusted
    {
        this.equalName = &equalCase!S;
        this._ownerDocument = null;
        this._qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
        this._buffers = new XmlBufferList!(S, No.CheckEncoded)();
    }

    final override bool allowChild() const nothrow
    {
        return true;
    }

    final override bool allowChildType(XmlNodeType nodeType) nothrow
    {
        switch (nodeType)
        {
            case XmlNodeType.comment:
            case XmlNodeType.processingInstruction:
            case XmlNodeType.significantWhitespace:
            case XmlNodeType.whitespace:
                return true;
            case XmlNodeType.declaration:
                return documentDeclaration is null;
            case XmlNodeType.documentType:
                return documentType is null;
            case XmlNodeType.element:
                return documentElement is null;
            default:
                return false;
        }
    }


    /** Load a content xml from a XmlReader, reader, and returns its' document
    Params:
        reader = a content xml reader to tokenize the text
        parseOptions = control behaviors of xml parser
    Returns:
        self document instance
    */
    final XmlDocument!S load(Flag!"SAX" SAX = No.SAX)(XmlReader!S reader, XmlParseOptions!S parseOptions)
    {
      ++_loading;
      scope (exit)
          --_loading;

      removeAll();

      auto parser = XmlParser!(S, SAX)(this, reader, parseOptions);
      return parser.parse();
    }

    /** Load a xml-string, xml, and returns its' document
    Params:
        xml = a xml string
        parseOptions = control behaviors of xml parser
    Returns:
        self document instance
    */
    final XmlDocument!S load(Flag!"SAX" SAX = No.SAX)(S xml,
        XmlParseOptions!S parseOptions = XmlParseOptions!S.init)
    {
        auto reader = new XmlStringReader!S(xml);
        return load!SAX(reader, parseOptions);
    }

    /** Load a content xml from a file-name, fileName, and returns its' document
    Params:
        fileName = a xml content file-name to be loaded from
        parseOptions = control behaviors of xml parser
    Returns:
        self document instance
    */
    final XmlDocument!S loadFromFile(Flag!"SAX" SAX = No.SAX)(string fileName,
        XmlParseOptions!S parseOptions = XmlParseOptions!S.init)
    {
      auto reader = new XmlFileReader!S(fileName);
      scope (exit)
          reader.close();

      return load!SAX(reader, parseOptions);
    }

    static XmlDocument!S opCall(Flag!"SAX" SAX = No.SAX)(S xml,
        XmlParseOptions!S parseOptions = XmlParseOptions!S.init)
    {
        auto doc = new XmlDocument!S();
		return doc.load!SAX(xml, parseOptions);
	}

    /** Write the document xml into a file-name, fileName, and returns fileName
    Params:
        fileName = an actual file-name to be written to
        prettyOutput = indicates if xml should be in nicer format
    Returns:
        fileName
    */
    final string saveToFile(string fileName,
        Flag!"prettyOutput" prettyOutput = No.prettyOutput)
    {
        auto writer = new XmlFileWriter!S(fileName, prettyOutput);
        scope (exit)
            writer.close();

        write(writer);
        return fileName;
    }

    XmlAttribute!S createAttribute(S name) nothrow
    {
        return new XmlAttribute!S(this, createName(name));
    }

    XmlAttribute!S createAttribute(S name, S value) nothrow
    {
        return new XmlAttribute!S(this, createName(name), value);
    }

    XmlAttribute!S createAttribute(S prefix, S localName, S namespaceUri) nothrow
    {
        return new XmlAttribute!S(this, createName(prefix, localName, namespaceUri));
    }

    XmlCData!S createCData(S data) nothrow
    {
        return new XmlCData!S(this, data);
    }

    XmlComment!S createComment(S text) nothrow
    {
        return new XmlComment!S(this, text);
    }

    XmlDeclaration!S createDeclaration() nothrow
    {
        return new XmlDeclaration!S(this);
    }

    XmlDeclaration!S createDeclaration(S versionStr, S encoding, bool standalone) nothrow
    {
        return new XmlDeclaration!S(this, versionStr, encoding, standalone);
    }

    XmlDocumentType!S createDocumentType(S name) nothrow
    {
        return new XmlDocumentType!S(this, name);
    }

    XmlDocumentType!S createDocumentType(S name, S publicOrSystem, S publicId, S text) nothrow
    {
        return new XmlDocumentType!S(this, name, publicOrSystem, publicId, text);
    }

    XmlDocumentTypeAttributeList!S createDocumentTypeAttributeList(S name) nothrow
    {
        return new XmlDocumentTypeAttributeList!S(this, name);
    }

    XmlDocumentTypeElement!S createDocumentTypeElement(S name) nothrow
    {
        return new XmlDocumentTypeElement!S(this, name);
    }

    XmlElement!S createElement(S name) nothrow
    {
        return new XmlElement!S(this, createName(name));
    }

    XmlElement!S createElement(S prefix, S localName, S namespaceUri) nothrow
    {
        return new XmlElement!S(this, createName(prefix, localName, namespaceUri));
    }

    XmlEntity!S createEntity(S name, S value) nothrow
    {
        return new XmlEntity!S(this, name, value);
    }

    XmlEntity!S createEntity(S name, S publicOrSystem, S publicId, S text, S notationName) nothrow
    {
        return new XmlEntity!S(this, name, publicOrSystem, publicId, text, notationName);
    }

    XmlEntityReference!S createEntityReference(S name, S text) nothrow
    {
        return new XmlEntityReference!S(this, name, text);
    }

    XmlEntityReference!S createEntityReference(S name, S publicOrSystem, S publicId, S text)
    {
        return new XmlEntityReference!S(this, name, publicOrSystem, publicId, text);
    }

    XmlNotation!S createNotation(S name, S publicOrSystem, S publicId, S text) nothrow
    {
        return new XmlNotation!S(this, name, publicOrSystem, publicId, text);
    }

    XmlProcessingInstruction!S createProcessingInstruction(S target, S text) nothrow
    {
        return new XmlProcessingInstruction!S(this, target, text);
    }

    XmlSignificantWhitespace!S createSignificantWhitespace(S text) nothrow
    {
        return new XmlSignificantWhitespace!S(this, text);
    }

    XmlText!S createText(S text) nothrow
    {
        return new XmlText!S(this, text);
    }

    XmlWhitespace!S createWhitespace(S text) nothrow
    {
        return new XmlWhitespace!S(this, text);
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        if (hasChildNodes)
            writeChildren(writer);

        return writer;
    }

    @property final override XmlDocument!S document() nothrow pure
    {
        return this;
    }

    /** Returns the xml declaration node if any, null otherwise
    */
    @property final XmlDeclaration!S documentDeclaration() nothrow
    {
        return cast(XmlDeclaration!S)findChild(XmlNodeType.declaration);
    }

    /** Returns the xml element node (root one) if any, null otherwise
    */
    @property final XmlElement!S documentElement() nothrow
    {
        return cast(XmlElement!S)findChild(XmlNodeType.element);
    }

    /** Returns the xml document-type node if any, null otherwise
    */
    @property final XmlDocumentType!S documentType() nothrow
    {
        return cast(XmlDocumentType!S)findChild(XmlNodeType.documentType);
    }

    /** Returns its entityTable; allow customized entity mapped values
    */
    @property final XmlEntityTable!S entityTable()
    {
        if (_entityTable is null)
            _entityTable = new XmlEntityTable!S();
        return _entityTable;
    }

    @property final override XmlNodeType nodeType() const nothrow pure
    {
        return XmlNodeType.document;
    }

package:
    pragma (inline, true)
    final S addSymbol(S symbol) nothrow
    in
    {
        assert(symbol.length != 0);
    }
    do
    {
        return _symbolTable.put(symbol);
    }

    pragma (inline, true)
    final S addSymbolIf(S symbol) nothrow
    {
        if (symbol.length == 0 || !useSymbolTable)
            return symbol;
        else
            return addSymbol(symbol);
    }

    pragma (inline, true)
    final XmlName!S createName(S qualifiedName)
    {
        return new XmlName!S(this, qualifiedName);
    }

    pragma (inline, true)
    final XmlName!S createName(S prefix, S localName, S namespaceUri)
    {
        return new XmlName!S(this, prefix, localName, namespaceUri);
    }

    final const(XmlEntityTable!S) decodeEntityTable()
    {
        if (_entityTable is null)
            return XmlEntityTable!S.defaultEntityTable();
        else
            return _entityTable;
    }

package:
    XmlDocumentTypeAttributeListDef!S createAttributeListDef(XmlDocumentTypeAttributeListDefType!S defType,
        S defaultType, XmlString!S defaultText)
    {
        return new XmlDocumentTypeAttributeListDef!S(this, defType, defaultType, defaultText);
    }

    XmlDocumentTypeAttributeListDefType!S createAttributeListDefType(S name, S type, S[] typeItems)
    {
        return new XmlDocumentTypeAttributeListDefType!S(this, name, type, typeItems);
    }

    XmlAttribute!S createAttribute(S name, XmlString!S text)
    {
        return new XmlAttribute!S(this, createName(name), text);
    }

    XmlComment!S createComment(XmlString!S text)
    {
        return new XmlComment!S(this, text);
    }

    XmlDocumentType!S createDocumentType(S name, S publicOrSystem, XmlString!S publicId, XmlString!S text)
    {
        return new XmlDocumentType!S(this, name, publicOrSystem, publicId, text);
    }

    XmlEntity!S createEntity(S name, XmlString!S text)
    {
        return new XmlEntity!S(this, name, text);
    }

    XmlEntity!S createEntity(S name, S publicOrSystem, XmlString!S publicId, XmlString!S text, S notationName)
    {
        return new XmlEntity!S(this, name, publicOrSystem, publicId, text, notationName);
    }

    XmlEntityReference!S createEntityReference(S name, XmlString!S text)
    {
        return new XmlEntityReference!S(this, name, text);
    }

    XmlEntityReference!S createEntityReference(S name, S publicOrSystem, XmlString!S publicId, XmlString!S text)
    {
        return new XmlEntityReference!S(this, name, publicOrSystem, publicId, text);
    }

    XmlNotation!S createNotation(S name, S publicOrSystem, XmlString!S publicId, XmlString!S text)
    {
        return new XmlNotation!S(this, name, publicOrSystem, publicId, text);
    }

    XmlProcessingInstruction!S createProcessingInstruction(S target, XmlString!S text)
    {
        return new XmlProcessingInstruction!S(this, target, text);
    }

    XmlText!S createText(XmlString!S text)
    {
        return new XmlText!S(this, text);
    }

protected:
    pragma (inline, true)
    final XmlBuffer!(S, No.CheckEncoded) acquireBuffer(XmlNodeType fromNodeType,
        size_t capacity = 0) nothrow
    {
        auto b = _buffers.acquire();
        if (capacity == 0 && fromNodeType == XmlNodeType.document)
            capacity = 64000;
        if (capacity != 0)
            b.capacity = capacity;

        return b;
    }

    static XmlName!S createDefaultQualifiedName() nothrow pure
    {
        return new XmlName!S(XmlConst!S.documentTagName);
    }

    pragma (inline, true)
    final S getAndReleaseBuffer(XmlBuffer!(S, No.CheckEncoded) b) nothrow
    {
        return _buffers.getAndRelease(b);
    }

    final S getDecodedText(ref XmlString!S s) nothrow
    {
        if (s.needDecode())
        {
            auto buffer = acquireBuffer(XmlNodeType.text, s.length);
            scope (exit)
                releaseBuffer(buffer);

            return s.decodedText!(XmlDecodeMode.loose)(buffer, decodeEntityTable());
        }
        else
            return s.rawValue();
    }

    final S getEncodedText(ref XmlString!S s) nothrow
    {
        if (s.needEncode())
        {
            auto buffer = acquireBuffer(XmlNodeType.text, s.length);
            scope (exit)
                releaseBuffer(buffer);

            return s.encodedText(buffer);
        }
        else
            return s.rawValue();
    }

    final override bool isLoading() nothrow pure
    {
        return _loading != 0;
    }

    pragma (inline, true)
    final void releaseBuffer(XmlBuffer!(S, No.CheckEncoded) b) nothrow
    {
        _buffers.release(b);
    }

    final override XmlDocument!S selfOwnerDocument() nothrow pure
    {
        return this;
    }

protected:
    XmlBufferList!(S, No.CheckEncoded) _buffers;
    XmlEntityTable!S _entityTable;
    XmlIdentifierList!S _symbolTable;
    int _loading;

private:
    __gshared static XmlName!S _defaultQualifiedName;
}

/** A xml document-fragment node object
*/
class XmlDocumentFragment(S = string) : XmlNode!S
{
@safe:

public:
    final override bool allowChild() const nothrow
    {
        return true;
    }

    final override bool allowChildType(XmlNodeType nodeType) nothrow
    {
        switch (nodeType)
        {
            case XmlNodeType.cdata:
            case XmlNodeType.comment:
            case XmlNodeType.element:
            case XmlNodeType.entity:
            case XmlNodeType.entityReference:
            case XmlNodeType.notation:
            case XmlNodeType.processingInstruction:
            case XmlNodeType.significantWhitespace:
            case XmlNodeType.text:
            case XmlNodeType.whitespace:
                return true;
            default:
                return false;
        }
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        if (hasChildNodes)
            writeChildren(writer);

        return writer;
    }

    @property final override XmlNodeType nodeType() const nothrow pure
    {
        return XmlNodeType.documentFragment;
    }

protected:
    static shared XmlName!S qualifiedName;

    static XmlName!S createQualifiedName()
    {
        return new XmlName!S(null, XmlConst!S.documentFragmentTagName);
    }
}

/** A xml document-type node object
*/
class XmlDocumentType(S = string) : XmlNode!S
{
@safe:

public:
    this(XmlDocument!S ownerDocument, S name) nothrow
    {
        this._ownerDocument = ownerDocument;
        this._qualifiedName = new XmlName!S(name);
    }

    this(XmlDocument!S ownerDocument, S name, S publicOrSystem, S publicId, S text) nothrow
    {
        this(ownerDocument, name);
        this._publicOrSystem = publicOrSystem;
        this._publicId = XmlString!S(publicId);
        this._text = XmlString!S(text);
    }

    this(XmlDocument!S ownerDocument, S name, S publicOrSystem, XmlString!S publicId, XmlString!S text) nothrow
    {
        this(ownerDocument, name);
        this._publicOrSystem = publicOrSystem;
        this._publicId = publicId;
        this._text = text;
    }

    final override bool allowChild() const nothrow
    {
        return true;
    }

    final override bool allowChildType(XmlNodeType nodeType) nothrow
    {
        switch (nodeType)
        {
            case XmlNodeType.comment:
            case XmlNodeType.documentTypeAttributeList:
            case XmlNodeType.documentTypeElement:
            case XmlNodeType.entity:
            case XmlNodeType.entityReference:
            case XmlNodeType.notation:
            case XmlNodeType.processingInstruction:
            case XmlNodeType.significantWhitespace:
            case XmlNodeType.text:
            case XmlNodeType.whitespace:
                return true;
            default:
                return false;
        }
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        //Flag!"hasChild"
        const c = hasChildNodes ? Yes.hasChild : No.hasChild;

        writer.putDocumentTypeBegin(name, publicOrSystem,
            ownerDocument.getEncodedText(_publicId), ownerDocument.getEncodedText(_text), c);
        if (c)
            writeChildren(writer);
        writer.putDocumentTypeEnd(c);

        return writer;
    }

    @property final override XmlNodeType nodeType() const nothrow pure
    {
        return XmlNodeType.documentType;
    }

    @property final S publicId() nothrow
    {
        return ownerDocument.getDecodedText(_publicId);
    }

    @property final S publicId(S newValue) nothrow
    {
        _publicId = newValue;
        return newValue;
    }

    @property final S publicOrSystem() nothrow
    {
        return _publicOrSystem;
    }

    @property final S publicOrSystem(S newValue) nothrow
    {
        const equalName = document.equalName;
        if (newValue.length == 0 ||
            newValue == XmlConst!S.public_ ||
            newValue == XmlConst!S.system)
            return _publicOrSystem = newValue;
        else
            return null;
    }

    @property final override S value() nothrow
    {
        return ownerDocument.getDecodedText(_text);
    }

    @property final override XmlNode!S value(S newValue) nothrow
    {
        _text = newValue;
        return this;
    }

protected:
    final override bool hasValueImpl() const nothrow pure
    {
        return _text.length != 0;
    }

protected:
    S _publicOrSystem;
    XmlString!S _publicId;
    XmlString!S _text;
}

class XmlDocumentTypeAttributeList(S = string) : XmlNode!S
{
@safe:

public:
    this(XmlDocument!S ownerDocument, S name)
    {
        this._ownerDocument = ownerDocument;
        this._qualifiedName = new XmlName!S(name);
    }

    final void appendDef(XmlDocumentTypeAttributeListDef!S item)
    {
        _defs ~= item;
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        writer.putDocumentTypeAttributeListBegin(name);
        foreach (e; _defs)
            e.write(writer);
        writer.putDocumentTypeAttributeListEnd();

        return writer;
    }

    @property final override XmlNodeType nodeType() const nothrow pure
    {
        return XmlNodeType.documentTypeAttributeList;
    }

protected:
    XmlDocumentTypeAttributeListDef!S[] _defs;
}

class XmlDocumentTypeAttributeListDef(S = string) : XmlObject!S
{
public:
    this(XmlDocument!S ownerDocument, XmlDocumentTypeAttributeListDefType!S type,
        S defaultDeclareType, S defaultDeclareText)
    {
        this(ownerDocument, type, defaultDeclareType, XmlString!S(defaultDeclareText));
    }

    final XmlWriter!S write(XmlWriter!S writer)
    {
        if (_type !is null)
            _type.write(writer);

        if (_defaultDeclareType.length != 0)
            writer.putWithPreSpace(_defaultDeclareType);

        if (_defaultDeclareText.length != 0)
        {
            writer.put(' ');
            writer.putWithQuote(ownerDocument.getEncodedText(_defaultDeclareText));
        }

        return writer;
    }

    @property final S defaultDeclareText()
    {
        return ownerDocument.getDecodedText(_defaultDeclareText);
    }

    @property final S defaultDeclareType() nothrow
    {
        return _defaultDeclareType;
    }

    @property final XmlDocument!S ownerDocument() nothrow pure
    {
        return _ownerDocument;
    }

    @property final XmlDocumentTypeAttributeListDefType!S type() nothrow
    {
        return _type;
    }

package:
    this(XmlDocument!S ownerDocument, XmlDocumentTypeAttributeListDefType!S type,
         S defaultDeclareType, XmlString!S defaultDeclareText)
    {
        this._ownerDocument = ownerDocument;
        this._type = type;
        this._defaultDeclareType = defaultDeclareType;
        this._defaultDeclareText = defaultDeclareText;
    }

protected:
    XmlDocument!S _ownerDocument;
    XmlDocumentTypeAttributeListDefType!S _type;
    XmlString!S _defaultDeclareText;
    S _defaultDeclareType;
}

class XmlDocumentTypeAttributeListDefType(S = string) : XmlObject!S
{
public:
    this(XmlDocument!S ownerDocument, S name, S type, S[] items)
    {
        this._ownerDocument = ownerDocument;
        this._name = name;
        this._type = type;
        this._items = items;
    }

    final void appendItem(S item)
    {
        _items ~= item;
    }

    final XmlWriter!S write(XmlWriter!S writer)
    {
        writer.put(_name);
        writer.putWithPreSpace(_type);
        foreach (e; _items)
            writer.putWithPreSpace(e);

        return writer;
    }

    @property final S localName() nothrow
    {
        return _name;
    }

    @property final S name() nothrow
    {
        return _name;
    }

    @property final XmlDocument!S ownerDocument() nothrow pure
    {
        return _ownerDocument;
    }

protected:
    XmlDocument!S _ownerDocument;
    S _name;
    S _type;
    S[] _items;
}

class XmlDocumentTypeElement(S = string) : XmlNode!S
{
@safe:

public:
    this(XmlDocument!S ownerDocument, S name)
    {
        this._ownerDocument = ownerDocument;
        this._qualifiedName = new XmlName!S(name);
    }

    final XmlDocumentTypeElementItem!S appendChoice(S choice)
    {
        auto item = new XmlDocumentTypeElementItem!S(ownerDocument, this, choice);
        _content ~= item;
        return item;
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        writer.putDocumentTypeElementBegin(name);

        if (_content.length != 0)
        {
            if (_content.length > 1)
                writer.put('(');
            _content[0].write(writer);
            foreach (e; _content[1..$])
            {
                writer.put(',');
                e.write(writer);
            }
            if (_content.length > 1)
                writer.put(')');
        }

        writer.putDocumentTypeElementEnd();

        return writer;
    }

    @property final XmlDocumentTypeElementItem!S[] content() nothrow
    {
        return _content;
    }

    @property final override XmlNodeType nodeType() const nothrow pure
    {
        return XmlNodeType.documentTypeElement;
    }

protected:
    XmlDocumentTypeElementItem!S[] _content;
}

class XmlDocumentTypeElementItem(S = string) : XmlObject!S
{
public:
    this(XmlDocument!S ownerDocument, XmlNode!S parent, S choice)
    {
        this._ownerDocument = ownerDocument;
        this._parent = parent;
        this._choice = choice;
    }

    XmlDocumentTypeElementItem!S appendChoice(S choice)
    {
        auto item = new XmlDocumentTypeElementItem!S(ownerDocument, parent, choice);
        _subChoices ~= item;
        return item;
    }

    final XmlWriter!S write(XmlWriter!S writer)
    {
        if (_choice.length != 0)
            writer.put(_choice);

        if (_subChoices.length != 0)
        {
            writer.put('(');
            _subChoices[0].write(writer);
            foreach (e; _subChoices[1..$])
            {
                writer.put('|');
                e.write(writer);
            }
            writer.put(')');
        }

        if (_multiIndicator != 0)
            writer.put(_multiIndicator);

        return writer;
    }

    @property final S choice() nothrow
    {
        return _choice;
    }

    @property final C multiIndicator() nothrow
    {
        return _multiIndicator;
    }

    @property final C multiIndicator(C newValue)
    {
        return _multiIndicator = newValue;
    }

    @property final XmlDocument!S ownerDocument() nothrow pure
    {
        return _ownerDocument;
    }

    @property final XmlNode!S parent() nothrow pure
    {
        return _parent;
    }

    @property final XmlDocumentTypeElementItem!S[] subChoices() nothrow
    {
        return _subChoices;
    }

protected:
    XmlDocument!S _ownerDocument;
    XmlNode!S _parent;
    XmlDocumentTypeElementItem!S[] _subChoices;
    S _choice; // EMPTY | ANY | #PCDATA | any-name
    C _multiIndicator = 0; // * | ? | + | blank
}

/** A xml element node object
*/
class XmlElement(S = string) : XmlNode!S
{
@safe:

public:
    this(XmlDocument!S ownerDocument, XmlName!S name) nothrow
    in
    {
        if (!ownerDocument.isLoading())
        {
            assert(isName!(S, Yes.AllowEmpty)(name.prefix));
            assert(isName!(S, No.AllowEmpty)(name.localName));
        }
    }
    do
    {
        this._ownerDocument = ownerDocument;
        this._qualifiedName = name;
    }

    final override bool allowAttribute() const nothrow
    {
        return true;
    }

    final override bool allowChild() const nothrow
    {
        return true;
    }

    final override bool allowChildType(XmlNodeType nodeType) nothrow
    {
        switch (nodeType)
        {
            case XmlNodeType.cdata:
            case XmlNodeType.comment:
            case XmlNodeType.element:
            case XmlNodeType.entityReference:
            case XmlNodeType.processingInstruction:
            case XmlNodeType.significantWhitespace:
            case XmlNodeType.text:
            case XmlNodeType.whitespace:
                return true;
            default:
                return false;
        }
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        const Flag!"hasAttribute" a = hasAttributes ? Yes.hasAttribute : No.hasAttribute;

        const Flag!"hasChild" c = hasChildNodes ? Yes.hasChild : No.hasChild;

        const onlyOneNodeText = isOnlyNode(firstChild) && firstChild.nodeType == XmlNodeType.text;
        if (onlyOneNodeText)
            writer.incOnlyOneNodeText();

        if (!a && !c)
            writer.putElementEmpty(name);
        else
        {
            writer.putElementNameBegin(name, a);

            if (a)
            {
                writeAttributes(writer);
                writer.putElementNameEnd(name, c);
            }

            if (c)
            {
                writeChildren(writer);
                writer.putElementEnd(name);
            }
        }

        if (onlyOneNodeText)
            writer.decOnlyOneNodeText();

        return writer;
    }

    @property final override XmlNodeType nodeType() const nothrow pure
    {
        return XmlNodeType.element;
    }

    alias localName = typeof(super).localName;

    @property final override XmlNode!S localName(S newName) nothrow
    {
        _qualifiedName = ownerDocument.createName(prefix, newName, namespaceUri);
        return this;
    }

    alias name = typeof(super).name;

    @property final override XmlNode!S name(S newName) nothrow
    {
        _qualifiedName = ownerDocument.createName(newName);
        return this;
    }

    alias namespaceUri = typeof(super).namespaceUri;

    @property final override XmlNode!S namespaceUri(S newUri) nothrow
    {
        _qualifiedName = ownerDocument.createName(prefix, localName, newUri);
        return this;
    }

    alias prefix = typeof(super).prefix;

    @property final override XmlNode!S prefix(S newPrefix) nothrow
    {
        _qualifiedName = ownerDocument.createName(newPrefix, localName, namespaceUri);
        return this;
    }
}

/** A xml entity node object
*/
class XmlEntity(S = string) : XmlEntityCustom!S
{
@safe:

public:
    this(XmlDocument!S ownerDocument, S name, S value)
    {
        super(ownerDocument, name, value);
    }

    this(XmlDocument!S ownerDocument, S name, S publicOrSystem, S publicId, S value, S notationName)
    {
        super(ownerDocument, name, publicOrSystem, publicId, value, notationName);
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        writer.putEntityGeneral(name, _publicOrSystem, ownerDocument.getEncodedText(_publicId),
            _notationName, ownerDocument.getEncodedText(_text));

        return writer;
    }

    @property final override XmlNodeType nodeType() const nothrow pure
    {
        return XmlNodeType.entity;
    }

package:
    this(XmlDocument!S ownerDocument, S name, XmlString!S value)
    {
        super(ownerDocument, name, value);
    }

    this(XmlDocument!S ownerDocument, S name, S publicOrSystem, XmlString!S publicId, XmlString!S value, S notationName)
    {
        super(ownerDocument, name, publicOrSystem, publicId, value, notationName);
    }
}

/** A xml entity-reference node object
*/
class XmlEntityReference(S = string) : XmlEntityCustom!S
{
@safe:

public:
    this(XmlDocument!S ownerDocument, S name, S value)
    {
        super(ownerDocument, name, value);
    }

    this(XmlDocument!S ownerDocument, S name, S publicOrSystem, S publicId, S value)
    {
        super(ownerDocument, name, publicOrSystem, publicId, value, null);
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        writer.putEntityReference(name, _publicOrSystem, ownerDocument.getEncodedText(_publicId),
            _notationName, ownerDocument.getEncodedText(_text));

        return writer;
    }

    @property final override XmlNodeType nodeType() const nothrow pure
    {
        return XmlNodeType.entityReference;
    }

package:
    this(XmlDocument!S ownerDocument, S name, XmlString!S value)
    {
        super(ownerDocument, name, value);
    }

    this(XmlDocument!S ownerDocument, S name, S publicOrSystem,
         XmlString!S publicId, XmlString!S value)
    {
        super(ownerDocument, name, publicOrSystem, publicId, value, null);
    }
}

/** A xml annotation node object
*/
class XmlNotation(S = string) : XmlNode!S
{
@safe:

public:
    this(XmlDocument!S ownerDocument, S name, S publicOrSystem, S publicId, S text) nothrow
    {
        this(ownerDocument, name);
        this._publicOrSystem = publicOrSystem;
        this._publicId = XmlString!S(publicId);
        this._text = XmlString!S(text);
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        writer.putNotation(name, publicOrSystem, ownerDocument.getEncodedText(_publicId),
            ownerDocument.getEncodedText(_text));

        return writer;
    }

    @property final override XmlNodeType nodeType() const nothrow pure
    {
        return XmlNodeType.notation;
    }

    @property final S publicId() nothrow
    {
        return ownerDocument.getDecodedText(_publicId);
    }

    @property final S publicOrSystem() nothrow
    {
        return _publicOrSystem;
    }

    @property final override S value() nothrow
    {
        return ownerDocument.getDecodedText(_text);
    }

    @property final override XmlNode!S value(S newValue) nothrow
    {
        _text = newValue;
        return this;
    }

package:
    this(XmlDocument!S ownerDocument, S name, S publicOrSystem,
         XmlString!S publicId, XmlString!S text) nothrow
    {
        this(ownerDocument, name);
        this._publicOrSystem = publicOrSystem;
        this._publicId = publicId;
        this._text = text;
    }

protected:
    this(XmlDocument!S ownerDocument, S name) nothrow
    {
        this._ownerDocument = ownerDocument;
        this._qualifiedName = new XmlName!S(name);
    }

    final override bool hasValueImpl() const nothrow pure
    {
        return _text.length != 0;
    }

protected:
    S _publicOrSystem;
    XmlString!S _publicId;
    XmlString!S _text;
}

/** A xml processing-instruction node object
*/
class XmlProcessingInstruction(S = string) : XmlNode!S
{
@safe:

public:
    this(XmlDocument!S ownerDocument, S target, S text) nothrow
    {
        this(ownerDocument, target);
        this._text = XmlString!S(text);
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        writer.putProcessingInstruction(name, ownerDocument.getEncodedText(_text));

        return writer;
    }

    @property final override S innerText()
    {
        return value;
    }

    @property final override XmlNode!S innerText(S newValue)
    {
        return value(newValue);
    }

    @property final override XmlNodeType nodeType() const nothrow pure
    {
        return XmlNodeType.processingInstruction;
    }

    @property final S target() nothrow
    {
        return _qualifiedName.name;
    }

    @property final override S value() nothrow
    {
        return ownerDocument.getDecodedText(_text);
    }

    @property final override XmlNode!S value(S newValue) nothrow
    {
        _text = newValue;
        return this;
    }

package:
    this(XmlDocument!S ownerDocument, S target, XmlString!S text) nothrow
    {
        this(ownerDocument, target);
        this._text = text;
    }

protected:
    this(XmlDocument!S ownerDocument, S target) nothrow
    {
        this._ownerDocument = ownerDocument;
        this._qualifiedName = new XmlName!S(target);
    }

    final override bool hasValueImpl() const nothrow pure
    {
        return _text.length != 0;
    }

protected:
    XmlString!S _text;
}

/** A xml significant-whitespace node object
*/
class XmlSignificantWhitespace(S = string) : XmlCharacterWhitespace!S
{
@safe:

public:
    this(XmlDocument!S ownerDocument, S text) nothrow @trusted
    {
        super(ownerDocument, text);
        this._qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
    }

    @property final override XmlNodeType nodeType() const nothrow pure
    {
        return XmlNodeType.significantWhitespace;
    }

protected:
    static XmlName!S createDefaultQualifiedName() nothrow pure
    {
        return new XmlName!S(XmlConst!S.significantWhitespaceTagName);
    }

private:
    __gshared static XmlName!S _defaultQualifiedName;
}

/** A xml text node object
*/
class XmlText(S = string) : XmlCharacterDataCustom!S
{
@safe:

public:
    this(XmlDocument!S ownerDocument, S text) nothrow @trusted
    {
        super(ownerDocument, text);
        this._qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        writer.put(ownerDocument.getEncodedText(_text));

        return writer;
    }

    @property final override size_t level() nothrow
    {
        return parent is null ? 0 : parent.level;
    }

    @property final override XmlNodeType nodeType() const nothrow pure
    {
        return XmlNodeType.text;
    }

package:
    this(XmlDocument!S ownerDocument, XmlString!S text) nothrow @trusted
    {
        super(ownerDocument, text);
        this._qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
    }

protected:
    static XmlName!S createDefaultQualifiedName() nothrow pure
    {
        return new XmlName!S(XmlConst!S.textTagName);
    }

private:
    __gshared static XmlName!S _defaultQualifiedName;
}

/** A xml whitespace node object
*/
class XmlWhitespace(S = string) : XmlCharacterWhitespace!S
{
@safe:

public:
    this(XmlDocument!S ownerDocument, S text) nothrow @trusted
    {
        super(ownerDocument, text);
        this._qualifiedName = singleton!(XmlName!S)(_defaultQualifiedName, &createDefaultQualifiedName);
    }

    @property final override XmlNodeType nodeType() const nothrow pure
    {
        return XmlNodeType.whitespace;
    }

protected:
    static XmlName!S createDefaultQualifiedName() nothrow pure
    {
        return new XmlName!S(XmlConst!S.whitespaceTagName);
    }

private:
    __gshared static XmlName!S _defaultQualifiedName;
}

/** A xml custom node object for any text type node object
*/
class XmlCharacterDataCustom(S = string) : XmlNode!S
{
@safe:

public:
    @property final override S innerText()
    {
        return value;
    }

    @property final override XmlNode!S innerText(S newValue)
    {
        return value(newValue);
    }

    @property override S value() nothrow
    {
        return ownerDocument.getDecodedText(_text);
    }

    @property override XmlNode!S value(S newValue) nothrow
    {
        _text = newValue;
        return this;
    }

protected:
    this(XmlDocument!S ownerDocument, S text) nothrow
    {
        this(ownerDocument, XmlString!S(text, XmlEncodeMode.check));
    }

    this(XmlDocument!S ownerDocument, S text, XmlEncodeMode mode) nothrow
    {
        this(ownerDocument, XmlString!S(text, mode));
    }

    this(XmlDocument!S ownerDocument, XmlString!S text) nothrow
    {
        this._ownerDocument = ownerDocument;
        this._text = text;
    }

    final override bool hasValueImpl() const nothrow pure
    {
        return _text.length != 0;
    }

    final override bool isText() const nothrow pure
    {
        return true;
    }

protected:
    XmlString!S _text;
}

/** A xml custom node object for whitespace or significant-whitespace node object
*/
class XmlCharacterWhitespace(S = string) : XmlCharacterDataCustom!S
{
@safe:

public:
    this(XmlDocument!S ownerDocument, S text) nothrow
    in
    {
        assert(ownerDocument.isLoading() || isSpaces!S(text));
    }
    do
    {
        super(ownerDocument, XmlString!S(text, XmlEncodeMode.none));
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        if (_text.length != 0)
            writer.put(_text.value);

        return writer;
    }

    @property final override size_t level() nothrow
    {
        return parent is null ? 0 : parent.level;
    }

    @property final override S value() nothrow
    {
        return _text.rawValue();
    }

    @property final override XmlNode!S value(S newValue) nothrow
    {
        if (!isSpaces!S(newValue))
        {
            Appender!S buffer;
            buffer.reserve(newValue.length);
            foreach (i; 0..newValue.length)
            {
                const c = newValue[i];
                if (isSpace(c))
                    buffer.put(c);
                else
                    buffer.put(' ');
            }
            _text = buffer.data;
        }
        else
            _text = newValue;
        return this;
    }
}

/** A xml custom node object for entity or entity-reference node object
*/
class XmlEntityCustom(S = string) : XmlNode!S
{
@safe:

public:
    this(XmlDocument!S ownerDocument, S name, S text) nothrow
    {
        this(ownerDocument, name);
        this._text = XmlString!S(text);
    }

    this(XmlDocument!S ownerDocument, S name, S publicOrSystem, S publicId, S text, S notationName) nothrow
    {
        this(ownerDocument, name);
        this._publicOrSystem = publicOrSystem;
        this._publicId = XmlString!S(publicId);
        this._text = XmlString!S(text);
        this._notationName = notationName;
    }

    @property final S notationName() const nothrow
    {
        return _notationName;
    }

    @property final S publicId()
    {
        return ownerDocument.getDecodedText(_publicId);
    }

    @property final S publicOrSystem() const nothrow
    {
        return _publicOrSystem;
    }

    @property final override S value() nothrow
    {
        return ownerDocument.getDecodedText(_text);
    }

    @property final override XmlNode!S value(S newValue) nothrow
    {
        _text = newValue;
        return this;
    }

protected:
    this(XmlDocument!S ownerDocument, S name) nothrow
    {
        this._ownerDocument = ownerDocument;
        this._qualifiedName = new XmlName!S(name);
    }

    this(XmlDocument!S ownerDocument, S name, XmlString!S text) nothrow
    {
        this(ownerDocument, name);
        this._text = text;
    }

    this(XmlDocument!S ownerDocument, S name, S publicOrSystem,
         XmlString!S publicId, XmlString!S text, S notationName) nothrow
    {
        this(ownerDocument, name);
        this._publicOrSystem = publicOrSystem;
        this._publicId = publicId;
        this._text = text;
        this._notationName = notationName;
    }

    final override bool hasValueImpl() const nothrow pure
    {
        return _text.length != 0;
    }

protected:
    S _notationName;
    S _publicOrSystem;
    XmlString!S _publicId;
    XmlString!S _text;
}

/** A xml name object
*/
class XmlName(S = string) : XmlObject!S
{
nothrow @safe:

public:
    this(XmlDocument!S ownerDocument, S prefix, S localName, S namespaceUri)
    in
    {
        assert(localName.length != 0);
    }
    do
    {
        this.ownerDocument = ownerDocument;
        this._prefix = ownerDocument.addSymbolIf(prefix);
        this._localName = ownerDocument.addSymbolIf(localName);
        this._namespaceUri = ownerDocument.addSymbolIf(namespaceUri);

        if (prefix.length == 0)
            this._name = localName;
    }

    this(XmlDocument!S ownerDocument, S qualifiedName)
    in
    {
        assert(qualifiedName.length != 0);
    }
    do
    {
        this.ownerDocument = ownerDocument;
        this._name = ownerDocument.addSymbolIf(qualifiedName);
    }

    @property final S localName()
    {
        if (_localName.length == 0)
            doSplitName();

        return _localName;
    }

    @property final S name()
    {
        if (_name.length == 0)
        {
            if (ownerDocument is null)
                _name = combineName!S(_prefix, _localName);
            else
                _name = ownerDocument.addSymbolIf(combineName!S(_prefix, _localName));
        }

        return _name;
    }

    @property final S namespaceUri()
    {
        if (_namespaceUri.ptr is null)
        {
            if ((XmlConst!S.xmlns == prefix) || (prefix.length == 0 && XmlConst!S.xmlns == localName))
                _namespaceUri = XmlConst!S.xmlnsNS;
            else if (XmlConst!S.xml == prefix)
                _namespaceUri = XmlConst!S.xmlNS;
            else if (ownerDocument !is null)
                _namespaceUri = ownerDocument.defaultUri;

            if (_namespaceUri.ptr is null)
                _namespaceUri = "";
        }

        return _namespaceUri;
    }

    @property final S prefix()
    {
        if (_prefix.ptr is null)
            doSplitName();

        return _prefix;
    }

package:
    this(S staticName)
    {
        this._localName = staticName;
        this._name = staticName;
        this._namespaceUri = "";
        this._prefix = "";
    }

protected:
    final void doSplitName()
    {
        if (_name.length != 0)
            splitName!S(_name, _prefix, _localName);

        if (_prefix.ptr is null)
            _prefix = "";
    }

protected:
    XmlDocument!S ownerDocument;
    S _localName;
    S _name;
    S _namespaceUri;
    S _prefix;
}

debug(PhamXml)
unittest  // Display object sizeof
{
    import std.stdio : writeln;

    debug writeln("");
    debug writeln("xml.XmlNodeList.sizeof: ", XmlNodeList!string.sizeof);
    debug writeln("xml.XmlAttribute.sizeof: ", XmlAttribute!string.classinfo.initializer.length);
    debug writeln("xml.XmlCData.sizeof: ", XmlCData!string.classinfo.initializer.length);
    debug writeln("xml.XmlComment.sizeof: ", XmlComment!string.classinfo.initializer.length);
    debug writeln("xml.XmlDeclaration.sizeof: ", XmlDeclaration!string.classinfo.initializer.length);
    debug writeln("xml.XmlDocument.sizeof: ", XmlDocument!string.classinfo.initializer.length);
    debug writeln("xml.XmlDocumentFragment.sizeof: ", XmlDocumentFragment!string.classinfo.initializer.length);
    debug writeln("xml.XmlDocumentType.sizeof: ", XmlDocumentType!string.classinfo.initializer.length);
    debug writeln("xml.XmlDocumentTypeAttributeList.sizeof: ", XmlDocumentTypeAttributeList!string.classinfo.initializer.length);
    debug writeln("xml.XmlDocumentTypeAttributeListDef.sizeof: ", XmlDocumentTypeAttributeListDef!string.classinfo.initializer.length);
    debug writeln("xml.XmlDocumentTypeAttributeListDefType.sizeof: ", XmlDocumentTypeAttributeListDefType!string.classinfo.initializer.length);
    debug writeln("xml.XmlDocumentTypeElement.sizeof: ", XmlDocumentTypeElement!string.classinfo.initializer.length);
    debug writeln("xml.XmlDocumentTypeElementItem.sizeof: ", XmlDocumentTypeElementItem!string.classinfo.initializer.length);
    debug writeln("xml.XmlElement.sizeof: ", XmlElement!string.classinfo.initializer.length);
    debug writeln("xml.XmlEntity.sizeof: ", XmlEntity!string.classinfo.initializer.length);
    debug writeln("xml.XmlEntityReference.sizeof: ", XmlEntityReference!string.classinfo.initializer.length);
    debug writeln("xml.XmlNotation.sizeof: ", XmlNotation!string.classinfo.initializer.length);
    debug writeln("xml.XmlProcessingInstruction.sizeof: ", XmlProcessingInstruction!string.classinfo.initializer.length);
    debug writeln("xml.XmlSignificantWhitespace.sizeof: ", XmlSignificantWhitespace!string.classinfo.initializer.length);
    debug writeln("xml.XmlText.sizeof: ", XmlText!string.classinfo.initializer.length);
    debug writeln("xml.XmlWhitespace.sizeof: ", XmlWhitespace!string.classinfo.initializer.length);
    debug writeln("xml.XmlCharacterWhitespace.sizeof: ", XmlCharacterWhitespace!string.classinfo.initializer.length);
    debug writeln("xml.XmlName.sizeof: ", XmlName!string.classinfo.initializer.length);
    debug writeln("xml.XmlParser.sizeof: ", XmlParser!string.sizeof);
    debug writeln("xml.XmlString.sizeof: ", XmlString!string.sizeof);
    debug writeln("xml.XmlBuffer.sizeof: ", XmlBuffer!(string, No.CheckEncoded).classinfo.initializer.length);
    debug writeln("xml.XmlBufferList.sizeof: ", XmlBufferList!(string, No.CheckEncoded).classinfo.initializer.length);
    debug writeln("");
}

version(unittest)
{
    private static immutable string sampleXml =
    "<?xml version=\"1.2\" encoding=\"utf8\" standalone=\"yes\"?>" ~
    "<root>" ~
        "<prefix_e:localname a0=\"\">withPrefix</prefix_e:localname>" ~
        "<a1 a1=\"value\"/>" ~
        "<a2 a2=\"&amp;&lt;&gt;&apos;&quot;\"/>" ~
        "<a3 prefix_a:a3=\"value\"/>" ~
        "<a4 id=\"123\"/>" ~
        "<c>" ~
            "<!----comment---->" ~
            "<cc/>" ~
        "</c>" ~
        "<t>text</t>" ~
        "<t>text2</t>" ~
        "<?target what to do with this processing instruction?>" ~
        "<![CDATA[data &<>]]>" ~
    "</root>";
}

unittest  // XmlDocument
{
    import std.conv : to;

    auto doc = new XmlDocument!string();

    doc.appendChild(doc.createDeclaration("1.2", "utf8", true));

    auto root = doc.appendChild(doc.createElement("root"));
    root.appendChild(doc.createElement("prefix_e", "localname", null).innerText("withPrefix"))
        .appendAttribute(doc.createAttribute("a0"));
    root.appendChild(doc.createElement("a1"))
        .appendAttribute(doc.createAttribute("a1", "value"));
    root.appendChild(doc.createElement("a2"))
        .appendAttribute(doc.createAttribute("a2", "&<>'\""));
    root.appendChild(doc.createElement("a3"))
        .appendAttribute(cast(XmlAttribute!string)doc.createAttribute("prefix_a", "a3", "localhost.com").value("value"));
    root.appendChild(doc.createElement("a4"))
        .appendAttribute("id").value("123");
    root.appendChild(doc.createElement("c"))
        .appendChild(doc.createComment("--comment--"))
        .parent.appendChild(doc.createElement("cc"));
    root.appendChild(doc.createElement("t"))
        .appendChild(doc.createText("text"));
    root.appendChild(doc.createElement("t"))
        .appendChild(doc.createText("text2"));
    root.appendChild(doc.createProcessingInstruction("target", "what to do with this processing instruction"));
    root.appendChild(doc.createCData("data &<>"));

    string dgOutputFailure()
    {
        return "\n" ~ doc.outerXml().to!string() ~ "\n" ~ sampleXml;
    }

    assert(doc.outerXml() == sampleXml, dgOutputFailure());

    doc = XmlDocument!string(sampleXml);
    assert(doc.documentElement !is null);
    assert(doc.outerXml() == sampleXml, dgOutputFailure());

    XmlElement!string e = doc.findElementById("123");
    assert(e);
    assert(e.name == "a4");
    assert(e.getAttribute("id") == "123", e.getAttribute("id"));

    e = doc.documentElement.findElement("t");
    assert(e !is null);
    assert(e.innerText == "text", e.innerText);

    e = doc.documentElement.findElement("xyz", Yes.deep);
    assert(e is null);

    e = doc.documentElement.findElement("cc", Yes.deep);
    assert(e !is null);
}

unittest // XmlNodeList
{
    import std.conv : to;

    auto doc = XmlDocument!string(sampleXml);

    size_t elementsLength, attributesLength;

    auto rootAttributes = doc.documentElement.getAttributes();
    assert(rootAttributes.empty);

    auto rootElements = doc.documentElement.getElements();
    assert(!rootElements.empty);
    assert(rootElements.length == 8);
    elementsLength = 0;
    while (!rootElements.empty)
    {
        elementsLength++;
        rootElements.popFront();
    }
    assert(elementsLength == 8);
    assert(rootElements.length == 0);
    assert(rootElements.empty);

    auto rootElementTags = doc.documentElement.getElementsByTagName("t");
    assert(!rootElementTags.empty);
    assert(rootElementTags.length == 2);
    elementsLength = 0;
    foreach (n; rootElementTags)
        elementsLength++;
    assert(elementsLength == 2);
    assert(rootElementTags.length == elementsLength, rootElementTags.length.to!string());
    assert(!rootElementTags.empty);

    auto rootElementTags2 = doc.documentElement.getElementsByTagName("localname", "*");
    assert(!rootElementTags2.empty);
    assert(rootElementTags2.length == 1);
    assert(rootElementTags2.item(0) !is null);
    assert(rootElementTags2.item(0).innerText == "withPrefix");
    assert(rootElementTags2["prefix_e:localname"] !is null);
    assert(rootElementTags2["prefix_e:localname"].innerText == "withPrefix");
    elementsLength = 0;
    while (!rootElementTags2.empty)
    {
        elementsLength++;
        rootElementTags2.popFront();
    }
    assert(elementsLength == 1);
    assert(rootElementTags2.length == 0);
    assert(rootElementTags2.empty);
}
