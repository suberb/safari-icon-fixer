import Foundation
var s = DemoSession()
let all = DemoSample.all
precondition(all.count == 8 && Set(all.map(\.id)).count == 8)
precondition(all.filter { s.missing($0) }.count == 3)
let a = DemoEdit(png: Data([1,2,3]), style: .systemTile)
let b = DemoEdit(png: Data([4,5]), style: .fullTile)
s.edit(0,a); precondition(!s.missing(all[0]) && s.current(0) == a && s.saved.isEmpty)
s.edit(-1,a); s.edit(2,DemoEdit(png: Data(),style:nil)); precondition(s.staged.count == 1)
s.discard(); precondition(s.missing(all[0]))
s.edit(0,a); s.apply(); precondition(s.staged.isEmpty && s.saved[0] == a)
s.edit(0,b); precondition(s.current(0) == b); s.discard(); precondition(s.current(0) == a)
s.edit(1,b); s.reset(); precondition(s.saved.isEmpty && s.staged.isEmpty && all.filter { s.missing($0) }.count == 3)
print("OK: isolated demo session, repair, edit, apply, discard, reset")
