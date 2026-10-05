import Foundation

/// Read-only Safari tab search; no JavaScript is executed in a webpage.
enum SafariTabScript {
    static let source = #"""
    ObjC.import('Foundation');
    function emit(value) {
        var line = $.NSString.alloc.initWithUTF8String(JSON.stringify(value)+'\n');
        $.NSFileHandle.fileHandleWithStandardOutput.writeData(line.dataUsingEncoding($.NSUTF8StringEncoding));
    }
    function normalize(v) { return String(v).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^\p{L}\p{N}]/gu,''); }
    emit({type:'ready'});
    while (true) {
        var data = $.NSFileHandle.fileHandleWithStandardInput.availableData;
        if (data.length === 0) break;
        var request;
        try {
            request = JSON.parse(ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data,$.NSUTF8StringEncoding)).trim());
            var safari = Application('com.apple.Safari');
            if (!safari.running()) throw new Error('closed');
            var windows = safari.windows().slice(0,20);
            if (request.op === 'snapshot') {
                var tabs=[], visited=0, unavailable=false;
                windows.forEach(function(window) {
                    window.tabs().slice(0,20).forEach(function(tab) {
                        if (visited++ >= 80) return;
                        var title=String(tab.name()), url=String(tab.url());
                        var matched=normalize(title+' '+url).indexOf(request.query)>=0;
                        if (!matched && request.contents && visited<=20 && /^https?:/i.test(url)) {
                            try { matched=normalize(String(tab.text()).slice(0,12000)).indexOf(request.query)>=0; }
                            catch (_) { unavailable=true; }
                        }
                        if (matched) tabs.push({windowID:window.id(),title:title.slice(0,180),url:url});
                    });
                });
                emit({id:request.id,tabs:tabs,contentUnavailable:unavailable});
            } else if (request.op === 'focus') {
                var window=windows.filter(function(w){return w.id()===request.windowID;})[0];
                if (!window) throw new Error('closed');
                var matches=window.tabs().filter(function(t){return t.url()===request.url;});
                if (matches.length!==1) throw new Error('ambiguous');
                var tab=matches[0];
                var matched=normalize(tab.name()+' '+tab.url()).indexOf(request.query)>=0;
                if (!matched && request.contents) matched=normalize(String(tab.text()).slice(0,12000)).indexOf(request.query)>=0;
                if (!matched) throw new Error('changed');
                window.currentTab=tab; window.index=1; safari.activate();
                emit({id:request.id,ok:true});
            } else throw new Error('invalid');
        } catch (_) {
            emit({id:request ? request.id : null,error:'Safari-Zugriff fehlgeschlagen. Bitte Automation für Friday erlauben; der Tab muss noch eindeutig offen sein.'});
        }
    }
    """#
}
