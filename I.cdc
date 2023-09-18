access(all) contract interface I {
    access(all) let a: {Int: Int}

    access(all) fun f(a: Int) {
        pre {
            self.a.containsKey(a)
        }
    } 
}