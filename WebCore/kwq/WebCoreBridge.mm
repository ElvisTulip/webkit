/*
 * Copyright (C) 2004 Apple Computer, Inc.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE COMPUTER, INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE COMPUTER, INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
 */

#import "WebCoreBridge.h"

#import "csshelper.h"
#import "dom_node.h"
#import "dom_docimpl.h"
#import "dom_nodeimpl.h"
#import "dom2_rangeimpl.h"
#import "htmlediting.h"
#import "html_documentimpl.h"
#import "html_formimpl.h"
#import "html_imageimpl.h"
#import "htmlattrs.h"
#import "htmltags.h"
#import "khtml_part.h"
#import "khtml_selection.h"
#import "khtmlview.h"
#import "kjs_proxy.h"
#import "kjs_window.h"
#import "loader.h"
#import "render_frames.h"
#import "render_image.h"
#import "render_object.h"
#import "render_canvas.h"
#import "render_style.h"
#import "render_replaced.h"

#import <JavaScriptCore/jni_jsobject.h>
#import <JavaScriptCore/object.h>
#import <JavaScriptCore/runtime_root.h>
#import <JavaScriptCore/property_map.h>

#import "KWQAssertions.h"
#import "KWQCharsets.h"
#import "KWQDOMNode.h"
#import "KWQEditCommand.h"
#import "KWQFont.h"
#import "KWQFrame.h"
#import "KWQLoader.h"
#import "KWQPageState.h"
#import "KWQRenderTreeDebug.h"
#import "KWQView.h"
#import "KWQPrinter.h"
#import "KWQAccObjectCache.h"

#import "DOMInternal.h"
#import "WebCoreImageRenderer.h"
#import "WebCoreTextRendererFactory.h"
#import "WebCoreViewFactory.h"
#import "WebCoreSettings.h"

#import <AppKit/NSView.h>

using DOM::AtomicString;
using DOM::DocumentImpl;
using DOM::DocumentTypeImpl;
using DOM::DOMString;
using DOM::Element;
using DOM::ElementImpl;
using DOM::HTMLFormElementImpl;
using DOM::HTMLGenericFormElementImpl;
using DOM::HTMLImageElementImpl;
using DOM::HTMLInputElementImpl;
using DOM::Node;
using DOM::NodeImpl;
using DOM::Range;

using khtml::Decoder;
using khtml::EditCommand;
using khtml::EditCommandImpl;
using khtml::parseURL;
using khtml::RenderCanvas;
using khtml::RenderImage;
using khtml::RenderObject;
using khtml::RenderPart;
using khtml::RenderStyle;
using khtml::RenderWidget;
using khtml::TypingCommand;

using KJS::SavedProperties;
using KJS::SavedBuiltins;

using KParts::URLArgs;

using KJS::Bindings::RootObject;

NSString *WebCoreElementDOMNodeKey =            @"WebCoreElementDOMNode"; // not in WebKit API for now, could be in API some day
NSString *WebCoreElementFrameKey =              @"WebElementFrame";
NSString *WebCoreElementImageAltStringKey = 	@"WebElementImageAltString";
NSString *WebCoreElementImageKey =              @"WebElementImage";
NSString *WebCoreElementImageRectKey =          @"WebElementImageRect";
NSString *WebCoreElementImageURLKey =           @"WebElementImageURL";
NSString *WebCoreElementIsEditableKey =         @"WebElementIsEditable";
NSString *WebCoreElementIsSelectedKey =         @"WebElementIsSelected";
NSString *WebCoreElementLinkURLKey =            @"WebElementLinkURL";
NSString *WebCoreElementLinkTargetFrameKey =	@"WebElementTargetFrame";
NSString *WebCoreElementLinkLabelKey =          @"WebElementLinkLabel";
NSString *WebCoreElementLinkTitleKey =          @"WebElementLinkTitle";
NSString *WebCoreElementNameKey =               @"WebElementName";
NSString *WebCoreElementTitleKey =              @"WebCoreElementTitle"; // not in WebKit API for now, could be in API some day

NSString *WebCorePageCacheStateKey =            @"WebCorePageCacheState";

static RootObject *rootForView(void *v)
{
    NSView *aView = (NSView *)v;
    WebCoreBridge *aBridge = [[WebCoreViewFactory sharedFactory] bridgeForView:aView];
    if (aBridge) {
        KWQKHTMLPart *part = [aBridge part];
        RootObject *root = new RootObject(v);    // The root gets deleted by JavaScriptCore.
        
        root->setRootObjectImp (static_cast<KJS::ObjectImp *>(KJS::Window::retrieveWindow(part)));
        root->setInterpreter (KJSProxy::proxy(part)->interpreter());
        part->addPluginRootObject (root);
            
        return root;
    }
    return 0;
}

@implementation WebCoreBridge

static bool initializedObjectCacheSize = FALSE;
static bool initializedKJS = FALSE;

- init
{
    [super init];
    
    _part = new KWQKHTMLPart;
    _part->setBridge(self);

    if (!initializedObjectCacheSize){
        khtml::Cache::setSize([self getObjectCacheSize]);
        initializedObjectCacheSize = TRUE;
    }
    
    if (!initializedKJS) {
        KJS::Bindings::RootObject::setFindRootObjectForNativeHandleFunction (rootForView);
        initializedKJS = TRUE;
    }
    
    _shouldCreateRenderers = YES;
    
    return self;
}

- (void)initializeSettings: (WebCoreSettings *)settings
{
    _part->setSettings ([settings settings]);
}

- (void)dealloc
{
    [self removeFromFrame];
    
    if (_renderPart) {
        _renderPart->deref(_renderPartArena);
    }
    _part->setBridge(nil);
    _part->deref();
        
    [super dealloc];
}

- (KWQKHTMLPart *)part
{
    return _part;
}

- (void)setRenderPart:(KHTMLRenderPart *)newPart;
{
    RenderArena *arena = newPart->ref();
    if (_renderPart) {
        _renderPart->deref(_renderPartArena);
    }
    _renderPart = newPart;
    _renderPartArena = arena;
}

- (KHTMLRenderPart *)renderPart
{
    return _renderPart;
}

- (void)setParent:(WebCoreBridge *)parent
{
    _part->setParent([parent part]);
}

- (void)provisionalLoadStarted
{
    _part->provisionalLoadStarted();
}


- (void)openURL:(NSURL *)URL reload:(BOOL)reload contentType:(NSString *)contentType refresh:(NSString *)refresh lastModified:(NSDate *)lastModified pageCache:(NSDictionary *)pageCache
{
    if (pageCache) {
        KWQPageState *state = [pageCache objectForKey:WebCorePageCacheStateKey];
        _part->openURLFromPageCache(state);
        [state invalidate];
        return;
    }
        
    // arguments
    URLArgs args(_part->browserExtension()->urlArgs());
    args.reload = reload;
    if (contentType) {
        args.serviceType = QString::fromNSString(contentType);
    }
    _part->browserExtension()->setURLArgs(args);

    // opening the URL
    if (_part->didOpenURL(URL)) {
        // things we have to set up after calling didOpenURL
        if (refresh) {
            _part->addMetaData("http-refresh", QString::fromNSString(refresh));
        }
        if (lastModified) {
            NSString *modifiedString = [lastModified descriptionWithCalendarFormat:@"%a %b %d %Y %H:%M:%S" timeZone:nil locale:nil];
            _part->addMetaData("modified", QString::fromNSString(modifiedString));
        }
    }
}

- (void)setEncoding:(NSString *)encoding userChosen:(BOOL)userChosen
{
    _part->setEncoding(QString::fromNSString(encoding), userChosen);
}

- (void)addData:(NSData *)data
{
    DocumentImpl *doc = _part->xmlDocImpl();
    
    // Document may be nil if the part is about to redirect
    // as a result of JS executing during load, i.e. one frame
    // changing another's location before the frame's document
    // has been created. 
    if (doc){
        doc->setShouldCreateRenderers([self shouldCreateRenderers]);
        _part->addData((const char *)[data bytes], [data length]);
    }
}

- (void)closeURL
{
    _part->closeURL();
}

- (void)didNotOpenURL:(NSURL *)URL
{
    _part->didNotOpenURL(KURL(URL).url());
}

- (void)saveDocumentState
{
    DocumentImpl *doc = _part->xmlDocImpl();
    if (doc != 0){
        QStringList list = doc->docState();
        NSMutableArray *documentState = [[[NSMutableArray alloc] init] autorelease];
        
        for (uint i = 0; i < list.count(); i++){
            QString s = list[i];
            [documentState addObject: [NSString stringWithCharacters: (const unichar *)s.unicode() length: s.length()]];
        }
        [self saveDocumentState: documentState];
    }
}

- (void)restoreDocumentState
{
    DocumentImpl *doc = _part->xmlDocImpl();
    
    if (doc != 0){
        NSArray *documentState = [self documentState];
        
        QStringList s;
        for (uint i = 0; i < [documentState count]; i++){
            NSString *string = [documentState objectAtIndex: i];
            s.append(QString::fromNSString(string));
        }
            
        doc->setRestoreState(s);
    }
}

- (void)scrollToAnchorWithURL:(NSURL *)URL
{
    _part->scrollToAnchor(KURL(URL).url().latin1());
}

- (BOOL)saveDocumentToPageCache
{
    DocumentImpl *doc = _part->xmlDocImpl();
    if (!doc) {
        return NO;
    }
    
    if (!doc->view()) {
        return NO;
    }
    _part->clearTimers();

    SavedProperties *windowProperties = new SavedProperties;
    _part->saveWindowProperties(windowProperties);

    SavedProperties *locationProperties = new SavedProperties;
    _part->saveLocationProperties(locationProperties);
    
    SavedBuiltins *interpreterBuiltins = new SavedBuiltins;
    _part->saveInterpreterBuiltins(*interpreterBuiltins);

    KWQPageState *pageState = [[[KWQPageState alloc] initWithDocument:doc
                                                                  URL:_part->m_url
                                                     windowProperties:windowProperties
                                                   locationProperties:locationProperties
				                  interpreterBuiltins:interpreterBuiltins] autorelease];
    [pageState setPausedActions: _part->pauseActions((const void *)pageState)];

    return [self saveDocumentToPageCache:pageState];
}

- (BOOL)canCachePage
{
    return _part->canCachePage();
}

- (void)end
{
    _part->end();
}

- (void)createKHTMLViewWithNSView:(NSView *)view marginWidth:(int)mw marginHeight:(int)mh
{
    // If we own the view, delete the old one - otherwise the render _part will take care of deleting the view.
    [self removeFromFrame];

    KHTMLView *kview = new KHTMLView(_part, 0);
    _part->setView(kview);
    kview->deref();

    kview->setView(view);
    if (mw >= 0)
        kview->setMarginWidth(mw);
    if (mh >= 0)
        kview->setMarginHeight(mh);
}

- (void)scrollToAnchor:(NSString *)a
{
    _part->gotoAnchor(QString::fromNSString(a));
}

- (BOOL)isSelectionEditable
{
	NodeImpl *startNode = _part->selection().startNode();
	return startNode ? startNode->isContentEditable() : NO;
}

- (BOOL)moveCaretToPoint:(NSPoint)point
{
    RenderObject *renderer = _part->renderer();
    if (!renderer) {
        return NO;
    }
    
    RenderObject::NodeInfo nodeInfo(true, true);
    renderer->layer()->nodeAtPoint(nodeInfo, (int)point.x, (int)point.y);
    NodeImpl *node = nodeInfo.innerNode();

    // FIXME: You should be move the caret to non-text nodes.
    if (!node->isTextNode()) {
        return NO;
    }
        
    NodeImpl *tempNode;
    int absX = 0;
    int absY = 0;
    int offset;
    node->renderer()->absolutePosition(absX, absY);
    node->renderer()->checkSelectionPoint((int)point.x, (int)point.y, absX, absY, tempNode, offset);
    
    KHTMLSelection selection(node, offset);
    _part->setSelection(selection);
    
    return YES;
}

- (void)pasteMarkupString:(NSString *)markupString
{
    _part->pasteHTMLString(QString::fromNSString(markupString));
}

- (void)pasteImageWithURL:(NSURL *)URL
{
    _part->pasteImage(QString::fromNSString([URL absoluteString]));
}

- (void)deleteSelection
{
    _part->deleteSelection();
}

- (BOOL)haveSelection
{
    return _part->selection().state() == KHTMLSelection::RANGE;
}

- (DOMRange *)selectedRange
{
    return [DOMRange _rangeWithImpl:_part->selection().toRange().handle()];
}

- (NSString *)_documentTypeString
{
    NSString *documentTypeString = nil;
    DOM::DocumentImpl *doc = _part->xmlDocImpl();
    if (doc) {
        DocumentTypeImpl *doctype = doc->doctype();
        if (doctype) {
            documentTypeString = doctype->toString().string().getNSString();
        }
    }
    return documentTypeString;
}

- (NSString *)_stringWithDocumentTypeStringAndMarkupString:(NSString *)markupString
{
    NSString *documentTypeString = [self _documentTypeString];
    if (documentTypeString && markupString) {
        return [NSString stringWithFormat:@"%@\n%@", documentTypeString, markupString];
    } else if (documentTypeString) {
        return documentTypeString;
    } else if (markupString) {
        return markupString;
    } else {
        return @"";
    }
}

- (NSString *)markupStringFromNode:(DOMNode *)node subresourceURLStrings:(NSArray **)subresourceURLStrings
{
    QStringList *subresourceURLs = NULL;
    if (subresourceURLStrings) {
        subresourceURLs = new QStringList();
    }
    NSString *markupString = [node _nodeImpl]->recursive_toHTMLWithOptions(true, false, NULL, subresourceURLs).getNSString();
    if (subresourceURLStrings) {
        *subresourceURLStrings = subresourceURLs->getNSArray();
    }
    return [self _stringWithDocumentTypeStringAndMarkupString:markupString];
}

- (NSString *)markupStringFromRange:(DOMRange *)range subresourceURLStrings:(NSArray **)subresourceURLStrings
{
    QStringList *subresourceURLs = NULL;
    if (subresourceURLStrings) {
        subresourceURLs = new QStringList();
    }
    NSString *markupString = [range _rangeImpl]->toHTMLWithOptions(false, subresourceURLs).string().getNSString();
    if (subresourceURLStrings) {
        *subresourceURLStrings = subresourceURLs->getNSArray();
    }
    return [self _stringWithDocumentTypeStringAndMarkupString:markupString];
}

- (NSString *)selectedString
{
    QString text = _part->selectedText();
    text.replace('\\', _part->backslashAsCurrencySymbol());
    return [[text.getNSString() copy] autorelease];
}

- (void)selectAll
{
    _part->selectAll();
}

- (void)deselectAll
{
    [self deselectText];
    DocumentImpl *doc = _part->xmlDocImpl();
    if (doc) {
        doc->setFocusNode(0);
    }
}

- (void)deselectText
{
    _part->slotClearSelection();
}

- (BOOL)isFrameSet
{
    return _part->isFrameSet();
}

- (NSString *)styleSheetForPrinting
{
    if (!_part->settings()->shouldPrintBackgrounds()) {
        return @"* { background-image: none !important; background-color: white !important;}";
    }
    return nil;
}

- (void)reapplyStylesForDeviceType:(WebCoreDeviceType)deviceType
{
    _part->setMediaType(deviceType == WebCoreDeviceScreen ? "screen" : "print");
    DocumentImpl *doc = _part->xmlDocImpl();
    if (doc) {
        static QPaintDevice screen;
        static QPrinter printer;
    	doc->setPaintDevice(deviceType == WebCoreDeviceScreen ? &screen : &printer);
        if (deviceType != WebCoreDeviceScreen) {
            doc->setPrintStyleSheet(QString::fromNSString([self styleSheetForPrinting]));
        }
    }
    return _part->reparseConfiguration();
}

static BOOL nowPrinting(WebCoreBridge *self)
{
    DocumentImpl *doc = self->_part->xmlDocImpl();
    return doc && doc->paintDevice() && doc->paintDevice()->devType() == QInternal::Printer;
}

// Set or unset the printing mode in the view.  We only toy with this if we're printing.
- (void)_setupRootForPrinting:(BOOL)onOrOff
{
    if (nowPrinting(self)) {
        RenderCanvas *root = static_cast<khtml::RenderCanvas *>(_part->xmlDocImpl()->renderer());
        if (root) {
            root->setPrintingMode(onOrOff);
        }
    }
}

- (void)forceLayoutAdjustingViewSize:(BOOL)flag
{
    [self _setupRootForPrinting:YES];
    _part->forceLayout();
    if (flag) {
        [self adjustViewSize];
    }
    [self _setupRootForPrinting:NO];
}

- (void)forceLayoutWithMinimumPageWidth:(float)minPageWidth maximumPageWidth:(float)maxPageWidth adjustingViewSize:(BOOL)flag
{
    [self _setupRootForPrinting:YES];
    _part->forceLayoutWithPageWidthRange(minPageWidth, maxPageWidth);
    if (flag) {
        [self adjustViewSize];
    }
    [self _setupRootForPrinting:NO];
}

- (void)sendResizeEvent
{
    _part->sendResizeEvent();
}

- (void)drawRect:(NSRect)rect withPainter:(QPainter *)p
{
    [self _setupRootForPrinting:YES];
    if (_drawSelectionOnly) {
        _part->paintSelectionOnly(p, QRect(rect));
    } else {
        _part->paint(p, QRect(rect));
    }
    [self _setupRootForPrinting:NO];
}

- (void)drawRect:(NSRect)rect
{
    QPainter painter(nowPrinting(self));
    painter.setUsesInactiveTextBackgroundColor(_part->usesInactiveTextBackgroundColor());
    painter.setDrawsFocusRing(_part->showsFirstResponder());
    [self drawRect:rect withPainter:&painter];
}

// Used by pagination code called from AppKit when a standalone web page is printed.
- (NSArray*)computePageRectsWithPrintWidth:(float)printWidth printHeight:(float)printHeight
{
    [self _setupRootForPrinting:YES];
    NSMutableArray* pages = [NSMutableArray arrayWithCapacity:5];
	if (printWidth == 0 || printHeight == 0) {
		return pages;
	}
	
    KHTMLView* view = _part->view();
    NSView* documentView = view->getDocumentView();
    if (!documentView)
        return pages;
	
    float currPageHeight = printHeight;
    float docHeight = NSHeight([documentView bounds]);
    float docWidth = NSWidth([documentView bounds]);
    
    // We need to give the part the opportunity to adjust the page height at each step.
    for (float i = 0; i < docHeight; i += currPageHeight) {
        float proposedBottom = kMin(docHeight, i + printHeight);
        _part->adjustPageHeight(&proposedBottom, i, proposedBottom, i);
        currPageHeight = kMax(1.0f, proposedBottom - i);
        for (float j = 0; j < docWidth; j += printWidth) {
            NSValue* val = [NSValue valueWithRect: NSMakeRect(j, i, printWidth, currPageHeight)];
            [pages addObject: val];
        }
    }
    [self _setupRootForPrinting:NO];
    
    return pages;
}

// This is to support the case where a webview is embedded in the view that's being printed
- (void)adjustPageHeightNew:(float *)newBottom top:(float)oldTop bottom:(float)oldBottom limit:(float)bottomLimit
{
    [self _setupRootForPrinting:YES];
    _part->adjustPageHeight(newBottom, oldTop, oldBottom, bottomLimit);
    [self _setupRootForPrinting:NO];
}

- (NSObject *)copyDOMNode:(NodeImpl *)node copier:(id <WebCoreDOMTreeCopier>)copier
{
    NSMutableArray *children = [[NSMutableArray alloc] init];
    for (NodeImpl *child = node->firstChild(); child; child = child->nextSibling()) {
        [children addObject:[self copyDOMNode:child copier:copier]];
    }
    NSObject *copiedNode = [copier nodeWithName:node->nodeName().string().getNSString()
                                          value:node->nodeValue().string().getNSString()
                                         source:node->recursive_toHTML(true).getNSString()
                                       children:children];
    [children release];
    return copiedNode;
}

- (NSObject *)copyDOMTree:(id <WebCoreDOMTreeCopier>)copier
{
    DocumentImpl *doc = _part->xmlDocImpl();
    if (!doc) {
        return nil;
    }
    return [self copyDOMNode:doc copier:copier];
}

- (NSObject *)copyRenderNode:(RenderObject *)node copier:(id <WebCoreRenderTreeCopier>)copier
{
    NSMutableArray *children = [[NSMutableArray alloc] init];
    for (RenderObject *child = node->firstChild(); child; child = child->nextSibling()) {
        [children addObject:[self copyRenderNode:child copier:copier]];
    }
          
    NSString *name = [[NSString alloc] initWithUTF8String:node->renderName()];
    
    RenderPart *nodeRenderPart = dynamic_cast<RenderPart *>(node);
    QWidget *widget = nodeRenderPart ? nodeRenderPart->widget() : 0;
    NSView *view = widget ? widget->getView() : nil;
    
    int nx, ny;
    node->absolutePosition(nx,ny);
    NSObject *copiedNode = [copier nodeWithName:name
                                       position:NSMakePoint(nx,ny)
                                           rect:NSMakeRect(node->xPos(), node->yPos(), node->width(), node->height())
                                           view:view
                                       children:children];
    
    [name release];
    [children release];
    
    return copiedNode;
}

- (NSObject *)copyRenderTree:(id <WebCoreRenderTreeCopier>)copier
{
    RenderObject *renderer = _part->renderer();
    if (!renderer) {
        return nil;
    }
    return [self copyRenderNode:renderer copier:copier];
}

- (void)removeFromFrame
{
    _part->setView(0);
}

- (void)installInFrame:(NSView *)view
{
    // If this isn't the main frame, it must have a render _part set, or it
    // won't ever get installed in the view hierarchy.
    ASSERT(self == [self mainFrame] || _renderPart != nil);

    _part->view()->setView(view);
    if (_renderPart) {
        _renderPart->setWidget(_part->view());
        // Now the render part owns the view, so we don't any more.
    }

    _part->view()->initScrollBars();
}

- (void)mouseDown:(NSEvent *)event
{
    _part->mouseDown(event);
}

- (void)mouseDragged:(NSEvent *)event
{
    _part->mouseDragged(event);
}

- (void)mouseUp:(NSEvent *)event
{
    _part->mouseUp(event);
}

- (void)mouseMoved:(NSEvent *)event
{
    _part->mouseMoved(event);
}

- (BOOL)sendContextMenuEvent:(NSEvent *)event
{
    return _part->sendContextMenuEvent(event);
}

- (DOMElement *)elementForView:(NSView *)view
{
    // FIXME: implemented currently for only a subset of the KWQ widgets
    if ([view conformsToProtocol:@protocol(KWQWidgetHolder)]) {
        NSView <KWQWidgetHolder> *widgetHolder = view;
        QWidget *widget = [widgetHolder widget];
        if (widget != nil) {
            NodeImpl *node = static_cast<const RenderWidget *>(widget->eventFilterObject())->element();
            return [DOMElement _elementWithImpl:static_cast<ElementImpl *>(node)];
        }
    }
    return nil;
}

static NSView *viewForElement(ElementImpl *elementImpl)
{
    RenderObject *renderer = elementImpl->renderer();
    if (renderer && renderer->isWidget()) {
        QWidget *widget = static_cast<const RenderWidget *>(renderer)->widget();
        if (widget) {
            widget->populate();
            return widget->getView();
        }
    }
    return nil;
}

static HTMLInputElementImpl *inputElementFromDOMElement(DOMElement *element)
{
    NodeImpl *node = [element _nodeImpl];
    if (node && idFromNode(node) == ID_INPUT) {
        return static_cast<HTMLInputElementImpl *>(node);
    }
    return nil;
}

static HTMLFormElementImpl *formElementFromDOMElement(DOMElement *element)
{
    NodeImpl *node = [element _nodeImpl];
    if (node && idFromNode(node) == ID_FORM) {
        return static_cast<HTMLFormElementImpl *>(node);
    }
    return nil;
}

- (DOMElement *)elementWithName:(NSString *)name inForm:(DOMElement *)form
{
    HTMLFormElementImpl *formElement = formElementFromDOMElement(form);
    if (formElement) {
        QPtrList<HTMLGenericFormElementImpl> elements = formElement->formElements;
        QString targetName = QString::fromNSString(name);
        for (unsigned int i = 0; i < elements.count(); i++) {
            HTMLGenericFormElementImpl *elt = elements.at(i);
            // Skip option elements, other duds
            if (elt->name() == targetName) {
                return [DOMElement _elementWithImpl:elt];
            }
        }
    }
    return nil;
}

- (BOOL)elementDoesAutoComplete:(DOMElement *)element
{
    HTMLInputElementImpl *inputElement = inputElementFromDOMElement(element);
    return inputElement != nil
        && inputElement->inputType() == HTMLInputElementImpl::TEXT
        && inputElement->autoComplete();
}

- (BOOL)elementIsPassword:(DOMElement *)element
{
    HTMLInputElementImpl *inputElement = inputElementFromDOMElement(element);
    return inputElement != nil
        && inputElement->inputType() == HTMLInputElementImpl::PASSWORD;
}

- (DOMElement *)formForElement:(DOMElement *)element;
{
    HTMLInputElementImpl *inputElement = inputElementFromDOMElement(element);
    if (inputElement) {
        HTMLFormElementImpl *formElement = inputElement->form();
        if (formElement) {
            return [DOMElement _elementWithImpl:formElement];
        }
    }
    return nil;
}

- (DOMElement *)currentForm
{
    HTMLFormElementImpl *formElement = _part->currentForm();
    return formElement ? [DOMElement _elementWithImpl:formElement] : nil;
}

- (NSArray *)controlsInForm:(DOMElement *)form
{
    NSMutableArray *results = nil;
    HTMLFormElementImpl *formElement = formElementFromDOMElement(form);
    if (formElement) {
        QPtrList<HTMLGenericFormElementImpl> elements = formElement->formElements;
        for (unsigned int i = 0; i < elements.count(); i++) {
            if (elements.at(i)->isEnumeratable()) {		// Skip option elements, other duds
                NSView *view = viewForElement(elements.at(i));
                if (view) {
                    if (!results) {
                        results = [NSMutableArray arrayWithObject:view];
                    } else {
                        [results addObject:view];
                    }
                }
            }
        }
    }
    return results;
}

- (NSString *)searchForLabels:(NSArray *)labels beforeElement:(DOMElement *)element
{
    return _part->searchForLabelsBeforeElement(labels, [element _elementImpl]);
}

- (NSString *)matchLabels:(NSArray *)labels againstElement:(DOMElement *)element
{
    return _part->matchLabelsAgainstElement(labels, [element _elementImpl]);
}

- (NSDictionary *)elementAtPoint:(NSPoint)point
{
    RenderObject *renderer = _part->renderer();
    if (!renderer) {
        return nil;
    }
    RenderObject::NodeInfo nodeInfo(true, true);
    renderer->layer()->nodeAtPoint(nodeInfo, (int)point.x, (int)point.y);
    
    NSMutableDictionary *element = [NSMutableDictionary dictionary];
    [element setObject:[NSNumber numberWithBool:_part->isPointInsideSelection((int)point.x, (int)point.y)]
                forKey:WebCoreElementIsSelectedKey];
    
    // Find the title in the nearest enclosing DOM node.
    // For <area> tags in image maps, walk the tree for the <area>, not the <img> using it.
    for (NodeImpl *titleNode = nodeInfo.innerNode(); titleNode; titleNode = titleNode->parentNode()) {
        if (titleNode->isElementNode()) {
            const AtomicString& title = static_cast<ElementImpl *>(titleNode)->getAttribute(ATTR_TITLE);
            if (!title.isNull()) {
                // We found a node with a title.
                QString titleText = title.string();
                titleText.replace('\\', _part->backslashAsCurrencySymbol());
                [element setObject:titleText.getNSString() forKey:WebCoreElementTitleKey];
                break;
            }
        }
    }

    NodeImpl *URLNode = nodeInfo.URLElement();
    if (URLNode) {
        ElementImpl *e = static_cast<ElementImpl *>(URLNode);
        
        const AtomicString& title = e->getAttribute(ATTR_TITLE);
        if (!title.isEmpty()) {
            QString titleText = title.string();
            titleText.replace('\\', _part->backslashAsCurrencySymbol());
            [element setObject:titleText.getNSString() forKey:WebCoreElementLinkTitleKey];
        }
        
        const AtomicString& link = e->getAttribute(ATTR_HREF);
        if (!link.isNull()) {
            if (e->firstChild()) {
                Range r(_part->document());
                r.setStartBefore(e->firstChild());
                r.setEndAfter(e->lastChild());
                QString t = _part->text(r);
                if (!t.isEmpty()) {
                    [element setObject:t.getNSString() forKey:WebCoreElementLinkLabelKey];
                }
            }
            QString URLString = parseURL(link).string();
            [element setObject:_part->xmlDocImpl()->completeURL(URLString).getNSString() forKey:WebCoreElementLinkURLKey];
        }
        
        DOMString target = e->getAttribute(ATTR_TARGET);
        if (target.isEmpty() && _part->xmlDocImpl()) {
            target = _part->xmlDocImpl()->baseTarget();
        }
        if (!target.isEmpty()) {
            [element setObject:target.string().getNSString() forKey:WebCoreElementLinkTargetFrameKey];
        }
    }

    NodeImpl *node = nodeInfo.innerNonSharedNode();
    if (node) {
        [element setObject:[NSNumber numberWithBool:node->isContentEditable()]
                    forKey:WebCoreElementIsEditableKey];
        
        [element setObject:[DOMNode _nodeWithImpl:node] forKey:WebCoreElementDOMNodeKey];
    
        if (node->renderer() && node->renderer()->isImage()) {
            RenderImage *r = static_cast<RenderImage *>(node->renderer());
            NSImage *image = r->pixmap().image();
            // Only return image information if there is an image.
            if (image && !r->isDisplayingError()) {
                [element setObject:r->pixmap().image() forKey:WebCoreElementImageKey];
                
                int x, y;
                if (r->absolutePosition(x, y)) {
                    NSValue *rect = [NSValue valueWithRect:NSMakeRect(x, y, r->contentWidth(), r->contentHeight())];
                    [element setObject:rect forKey:WebCoreElementImageRectKey];
                }
                
                ElementImpl *i = static_cast<ElementImpl*>(node);
        
                // FIXME: Code copied from RenderImage::updateFromElement; should share.
                DOMString attr;
                if (idFromNode(i) == ID_OBJECT) {
                    attr = i->getAttribute(ATTR_DATA);
                } else {
                    attr = i->getAttribute(ATTR_SRC);
                }
                if (!attr.isEmpty()) {
                    QString URLString = parseURL(attr).string();
                    [element setObject:_part->xmlDocImpl()->completeURL(URLString).getNSString() forKey:WebCoreElementImageURLKey];
                }
                
                // FIXME: Code copied from RenderImage::updateFromElement; should share.
                DOMString alt;
                if (idFromNode(i) == ID_INPUT)
                    alt = static_cast<HTMLInputElementImpl *>(i)->altText();
                else if (idFromNode(i) == ID_IMG)
                    alt = static_cast<HTMLImageElementImpl *>(i)->altText();
                if (!alt.isNull()) {
                    QString altText = alt.string();
                    altText.replace('\\', _part->backslashAsCurrencySymbol());
                    [element setObject:altText.getNSString() forKey:WebCoreElementImageAltStringKey];
                }
            }
        }
    }
    
    return element;
}

- (BOOL)searchFor:(NSString *)string direction:(BOOL)forward caseSensitive:(BOOL)caseFlag wrap:(BOOL)wrapFlag
{
    return _part->findString(string, forward, caseFlag, wrapFlag);
}

- (void)jumpToSelection
{
    _part->jumpToSelection();
}

- (void)setTextSizeMultiplier:(float)multiplier
{
    int newZoomFactor = (int)rint(multiplier * 100);
    if (_part->zoomFactor() == newZoomFactor) {
        return;
    }
    _part->setZoomFactor(newZoomFactor);
}

- (CFStringEncoding)textEncoding
{
    return KWQCFStringEncodingFromIANACharsetName(_part->encoding().latin1());
}

- (NSView *)nextKeyView
{
    DocumentImpl *doc = _part->xmlDocImpl();
    if (!doc) {
        return nil;
    }
    return _part->nextKeyView(doc->focusNode(), KWQSelectingNext);
}

- (NSView *)previousKeyView
{
    DocumentImpl *doc = _part->xmlDocImpl();
    if (!doc) {
        return nil;
    }
    return _part->nextKeyView(doc->focusNode(), KWQSelectingPrevious);
}

- (NSView *)nextKeyViewInsideWebFrameViews
{
    return _part->nextKeyViewInFrameHierarchy(0, KWQSelectingNext);
}

- (NSView *)previousKeyViewInsideWebFrameViews
{
    return _part->nextKeyViewInFrameHierarchy(0, KWQSelectingPrevious);
}

- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)string
{
    _part->createEmptyDocument();
    return _part->executeScript(QString::fromNSString(string), true).asString().getNSString();
}

- (DOMDocument *)DOMDocument
{
    return [DOMDocument _documentWithImpl:_part->xmlDocImpl()];
}

- (void)setSelectionFrom:(DOMNode *)start startOffset:(int)startOffset to:(DOMNode *)end endOffset:(int) endOffset
{
    DOMNode *startNode = start;
    DOMNode *endNode = end;
    KHTMLSelection selection([startNode _nodeImpl], startOffset, [endNode _nodeImpl], endOffset);
    _part->setSelection(selection);
}

- (NSAttributedString *)selectedAttributedString
{
    return _part->attributedString(_part->selectionStart(), _part->selectionStartOffset(), _part->selectionEnd(), _part->selectionEndOffset());
}

- (NSAttributedString *)attributedStringFrom:(DOMNode *)start startOffset:(int)startOffset to:(DOMNode *)end endOffset:(int)endOffset
{
    DOMNode *startNode = start;
    DOMNode *endNode = end;
    return _part->attributedString([startNode _nodeImpl], startOffset, [endNode _nodeImpl], endOffset);
}

- (DOMNode *)selectionStart
{
    return [DOMNode _nodeWithImpl:_part->selectionStart()];
}

- (int)selectionStartOffset
{
    return _part->selectionStartOffset();
}

- (DOMNode *)selectionEnd
{
    return [DOMNode _nodeWithImpl:_part->selectionEnd()];
}

- (int)selectionEndOffset
{
    return _part->selectionEndOffset();
}

- (NSRect)selectionRect
{
    return _part->selectionRect(); 
}

- (NSRect)visibleSelectionRect
{
    KHTMLView *view = _part->view();
    if (!view) {
        return NSZeroRect;
    }
    NSView *documentView = view->getDocumentView();
    if (!documentView) {
        return NSZeroRect;
    }
    return NSIntersectionRect(_part->selectionRect(), [documentView visibleRect]); 
}

- (NSImage *)selectionImage
{
    NSView *view = _part->view()->getDocumentView();
    if (!view) {
        return nil;
    }

    NSRect rect = [self visibleSelectionRect];
    NSRect bounds = [view bounds];
    NSImage *selectionImage = [[[NSImage alloc] initWithSize:rect.size] autorelease];
    [selectionImage setFlipped:YES];
    [selectionImage lockFocus];

    [NSGraphicsContext saveGraphicsState];
    CGContextTranslateCTM((CGContext *)[[NSGraphicsContext currentContext] graphicsPort],
                          -(NSMinX(rect) - NSMinX(bounds)), -(NSMinY(rect) - NSMinY(bounds)));

    _drawSelectionOnly = YES;
    [view drawRect:rect];
    _drawSelectionOnly = NO;

    [NSGraphicsContext restoreGraphicsState];
        
    [selectionImage unlockFocus];
    [selectionImage setFlipped:NO];

    return selectionImage;
}

- (void)setName:(NSString *)name
{
    _part->KHTMLPart::setName(QString::fromNSString(name));
}

- (NSString *)name
{
    return _part->name().getNSString();
}

- (NSURL *)URL
{
    return _part->url().getNSURL();
}

- (NSString *)referrer
{
    return _part->referrer().getNSString();
}

+ (NSString *)stringWithData:(NSData *)data textEncoding:(CFStringEncoding)textEncoding
{
    if (textEncoding == kCFStringEncodingInvalidId || textEncoding == kCFStringEncodingISOLatin1) {
        textEncoding = kCFStringEncodingWindowsLatin1;
    }
    return QTextCodec(textEncoding).toUnicode((const char*)[data bytes], [data length]).getNSString();
}

+ (NSString *)stringWithData:(NSData *)data textEncodingName:(NSString *)textEncodingName
{
    CFStringEncoding textEncoding = KWQCFStringEncodingFromIANACharsetName([textEncodingName lossyCString]);
    return [WebCoreBridge stringWithData:data textEncoding:textEncoding];
}

+ (void)updateAllViews
{
    for (QPtrListIterator<KWQKHTMLPart> it(KWQKHTMLPart::instances()); it.current(); ++it) {
        KWQKHTMLPart *part = it.current();
        [part->bridge() setNeedsReapplyStyles];
    }
}

- (BOOL)needsLayout
{
    RenderObject *renderer = _part->renderer();
    return renderer ? renderer->needsLayout() : false;
}

- (void)setNeedsLayout
{
    RenderObject *renderer = _part->renderer();
    if (renderer)
        renderer->setNeedsLayout(true);
}

- (BOOL)interceptKeyEvent:(NSEvent *)event toView:(NSView *)view
{
    return _part->keyEvent(event);
}

- (NSString *)renderTreeAsExternalRepresentation
{
    return externalRepresentation(_part->renderer()).getNSString();
}

- (void)setUsesInactiveTextBackgroundColor:(BOOL)uses
{
    _part->setUsesInactiveTextBackgroundColor(uses);
}

- (BOOL)usesInactiveTextBackgroundColor
{
    return _part->usesInactiveTextBackgroundColor();
}

- (void)setShowsFirstResponder:(BOOL)flag
{
    _part->setShowsFirstResponder(flag);
}

- (void)setShouldCreateRenderers:(BOOL)f
{
    _shouldCreateRenderers = f;
}

- (BOOL)shouldCreateRenderers
{
    return _shouldCreateRenderers;
}

- (int)numPendingOrLoadingRequests
{
    DocumentImpl *doc = _part->xmlDocImpl();
    
    if (doc)
        return KWQNumberOfPendingOrLoadingRequests (doc->docLoader());
    return 0;
}

- (NSColor *)bodyBackgroundColor
{
    return _part->bodyBackgroundColor();
}

- (void)adjustViewSize
{
    KHTMLView *view = _part->view();
    if (view)
        view->adjustViewSize();
}

-(id)accessibilityTree
{
    if (!_part || !_part->xmlDocImpl()) return nil;
    RenderCanvas* root = static_cast<khtml::RenderCanvas *>(_part->xmlDocImpl()->renderer());
    if (!root) return nil;
    return _part->xmlDocImpl()->getOrCreateAccObjectCache()->accObject(root);
}

- (void)undoEditing:(id)arg
{
    ASSERT([arg isKindOfClass:[KWQEditCommand class]]);
    
    EditCommand cmd([arg impl]);
    cmd.unapply();
}

- (void)redoEditing:(id)arg
{
    ASSERT([arg isKindOfClass:[KWQEditCommand class]]);
    
    EditCommand cmd([arg impl]);
    cmd.reapply();
}

- (DOMRange *)rangeByModifyingRange:(DOMRange *)range alteration:(WebSelectionAlteration)alteration direction:(WebSelectionDirection)direction granularity:(WebSelectionGranularity)granularity;
{
    // NOTE: The enums *must* match the very similar ones declared in ktml_selection.h
    NodeImpl *startContainer = [[range startContainer] _nodeImpl];
    NodeImpl *endContainer = [[range endContainer] _nodeImpl];
    KHTMLSelection selection(startContainer, [range startOffset], endContainer, [range endOffset]);
    selection.modify(static_cast<KHTMLSelection::EAlter>(alteration), 
                     static_cast<KHTMLSelection::EDirection>(direction), 
                     static_cast<KHTMLSelection::ETextGranularity>(granularity));
    return [DOMRange _rangeWithImpl:selection.toRange().handle()];
}

- (void)setSelectedDOMRange:(DOMRange *)range
{
    NodeImpl *startContainer = [[range startContainer] _nodeImpl];
    NodeImpl *endContainer = [[range endContainer] _nodeImpl];
    KHTMLSelection selection(startContainer, [range startOffset], endContainer, [range endOffset]);
    _part->setSelection(selection);
}

- (DOMRange *)selectedDOMRange
{
    return [DOMRange _rangeWithImpl:_part->selection().toRange().handle()];
}

- (void)insertText:(NSString *)text
{
    if (!_part || !_part->xmlDocImpl())
        return;
    
    DOMString s(text);
    TypingCommand::insertText(_part->xmlDocImpl(), s);
}

- (void)insertNewline
{
    if (!_part || !_part->xmlDocImpl())
        return;
    
    TypingCommand::insertNewline(_part->xmlDocImpl());
}

- (void)deleteKeyPressed
{
    if (!_part || !_part->xmlDocImpl())
        return;
    
    TypingCommand::deleteKeyPressed(_part->xmlDocImpl());
}

@end
