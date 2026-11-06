import Foundation

struct NoteTemplate: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    /// Template-specific structure instructions appended to the base system prompt.
    let instructions: String

    static let all: [NoteTemplate] = [
        NoteTemplate(
            id: "auto",
            name: "Automático",
            icon: "wand.and.stars",
            instructions: """
            Estrutura: abra com **## Resumo** em 2–3 frases e siga com seções que acompanhem a estrutura \
            das anotações rápidas do usuário (ou uma estrutura temática adequada quando elas forem escassas). \
            Termine com **## Itens de ação** (caixas de seleção em Markdown, incluindo responsável e prazo quando citados) \
            e **## Questões em aberto**, se houver.
            """
        ),
        NoteTemplate(
            id: "one-on-one",
            name: "1:1",
            icon: "person.2",
            instructions: """
            Esta é uma reunião individual. Estrutura: **## Resumo**, **Assuntos da outra pessoa**, \
            **Meus assuntos**, **Feedbacks trocados**, **Decisões**, **## Itens de ação** \
            (separados em "Meus" e "Da outra pessoa") e **Temas para a próxima conversa**.
            """
        ),
        NoteTemplate(
            id: "sales",
            name: "Vendas / Descoberta",
            icon: "dollarsign.circle",
            instructions: """
            Esta é uma conversa de vendas ou descoberta. Estrutura: **## Resumo** (temperatura da oportunidade em uma linha), \
            **Sobre o prospect** (empresa, cargo e contexto), **Dores** (com citações literais quando relevantes), \
            **Requisitos e critérios de sucesso**, **Orçamento / cronograma / processo decisório** \
            (marque o que não foi discutido como "não discutido"), **Objeções**, **## Itens de ação** e **Próximo passo** \
            (o único próximo passo acordado, com data se definida).
            """
        ),
        NoteTemplate(
            id: "standup",
            name: "Alinhamento / Sincronização",
            icon: "person.3",
            instructions: """
            Este é um alinhamento de equipe. Estrutura: **## Resumo**, **Atualizações por pessoa/tema** \
            (tópicos concisos), **Impedimentos**, **Decisões** e **## Itens de ação** com responsáveis.
            """
        ),
        NoteTemplate(
            id: "interview",
            name: "Entrevista",
            icon: "questionmark.bubble",
            instructions: """
            Esta é uma entrevista (de trabalho, pesquisa com usuários ou podcast). Estrutura: **## Resumo** \
            (avaliação geral), **Contexto**, **Destaques por tema** (com citações curtas nos momentos mais fortes), \
            **Sinais de alerta / preocupações** (somente quando houver evidência) e **## Próximos passos**.
            """
        ),
        NoteTemplate(
            id: "brainstorm",
            name: "Brainstorming",
            icon: "lightbulb",
            instructions: """
            Este é um brainstorming. Estrutura: **## Resumo**, **Ideias** (agrupadas por tema, mantendo cada ideia \
            distinta e destacando as melhores com uma justificativa curta), **Ideias adiadas/descartadas e por quê**, \
            **Decisões** e **## Itens de ação**.
            """
        ),
    ]

    static func byID(_ id: String) -> NoteTemplate {
        all.first { $0.id == id } ?? all[0]
    }
}
