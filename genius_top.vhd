-- ============================================================
-- Projeto: Jogo Genius / Simon - PUC Campinas
-- Disciplina: PI: Projetos de Sistemas Digitais
-- Alunos: Theo Rodrigues Saviello e Vinícius de Andrade
-- Professor: Ricardo Pannain
-- Plataforma: FPGA Altera DE2-115 (Cyclone IV E)
--
-- Mapeamento de periféricos:
--   KEY0 (PIN_M23) -> Cor 0 (LEDG0 / PIN_G19)   [Verde]
--   KEY1 (PIN_M21) -> Cor 1 (LEDG2 / PIN_E18)   [Amarelo]
--   KEY2 (PIN_N21) -> Cor 2 (LEDG4 / PIN_B18)   [Vermelho]
--   KEY3 (PIN_R24) -> Cor 3 (LEDG6 / PIN_F22)   [Azul]
--   KEY0 (longo)   -> Start / Reset
--   HEX0-HEX1     -> Pontuação (00-99)
--   LEDR[9:0]     -> Animação de Game Over
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity genius_top is
    port (
        CLOCK_50 : in  std_logic;                     -- Clock 50 MHz (PIN_Y2)

        -- Botões (ativos em nível baixo na DE2-115)
        KEY      : in  std_logic_vector(3 downto 0);  -- KEY[0..3]

        -- LEDs Verdes (LEDG) - indicadores do jogo
        LEDG     : out std_logic_vector(7 downto 0);

        -- LEDs Vermelhos (LEDR) - animação de erro
        LEDR     : out std_logic_vector(9 downto 0);

        -- Displays de 7 segmentos (ativos em nível baixo)
        HEX0     : out std_logic_vector(6 downto 0);
        HEX1     : out std_logic_vector(6 downto 0);
        HEX2     : out std_logic_vector(6 downto 0);
        HEX3     : out std_logic_vector(6 downto 0)
    );
end entity genius_top;

architecture rtl of genius_top is

    -- ===========================================================
    -- Constantes de temporização (clock = 50 MHz)
    -- ===========================================================
    constant CLK_FREQ       : integer := 50_000_000;
    constant LED_ON_TIME    : integer := CLK_FREQ / 2;   -- 500 ms LED aceso
    constant LED_OFF_TIME   : integer := CLK_FREQ / 5;   -- 200 ms intervalo
    constant DEBOUNCE_TIME  : integer := CLK_FREQ / 50;  -- 20 ms debounce
    constant TIMEOUT_TIME   : integer := CLK_FREQ * 5;   -- 5 s para resposta
    constant WIN_FLASH_TIME : integer := CLK_FREQ / 4;   -- 250 ms flash vitória
    constant LOSE_FLASH_TIME: integer := CLK_FREQ / 8;   -- 125 ms flash derrota
    constant NUM_FLASHES    : integer := 6;               -- nº de flashes Game Over

    -- ===========================================================
    -- Definição dos estados da FSM
    -- ===========================================================
    type t_state is (
        ST_IDLE,        -- Aguardando start
        ST_GEN_SEQ,     -- Gera novo elemento da sequência
        ST_SHOW_LEAD,   -- Intervalo antes de mostrar próximo LED
        ST_SHOW_SEQ,    -- Exibe LED atual da sequência
        ST_WAIT_USER,   -- Aguarda entrada do usuário
        ST_CHECK,       -- Verifica a entrada
        ST_WIN,         -- Rodada vencida
        ST_LOSE_FLASH,  -- Animação de derrota
        ST_LOSE         -- Game Over aguardando reset
    );

    signal state, next_state : t_state := ST_IDLE;

    -- ===========================================================
    -- LFSR de 8 bits (polinômio primitivo: x^8+x^6+x^5+x^4+1)
    -- ===========================================================
    signal lfsr         : std_logic_vector(7 downto 0) := "10110001";
    signal lfsr_feedback: std_logic;

    -- ===========================================================
    -- Memória de sequência (até 32 níveis)
    -- ===========================================================
    constant MAX_SEQ    : integer := 32;
    type t_seq_mem is array(0 to MAX_SEQ-1) of std_logic_vector(1 downto 0);
    signal seq_mem      : t_seq_mem := (others => "00");

    signal seq_len      : integer range 0 to MAX_SEQ := 0;  -- comprimento atual
    signal seq_idx      : integer range 0 to MAX_SEQ := 0;  -- ponteiro de exibição/verificação

    -- ===========================================================
    -- Sinais de debounce (KEY0..KEY3)
    -- ===========================================================
    signal key_synced   : std_logic_vector(3 downto 0);  -- sincronizado (ativo alto)
    signal key_pressed  : std_logic_vector(3 downto 0);  -- pulso único por pressionamento
    signal key_db_cnt   : integer range 0 to DEBOUNCE_TIME := 0;
    -- Debounce individual para cada tecla
    type t_db_cnt is array(0 to 3) of integer range 0 to DEBOUNCE_TIME;
    signal db_cnt       : t_db_cnt := (others => 0);
    signal db_stable    : std_logic_vector(3 downto 0) := (others => '0');
    signal db_prev      : std_logic_vector(3 downto 0) := (others => '0');

    -- ===========================================================
    -- Temporização geral
    -- ===========================================================
    signal timer        : integer range 0 to TIMEOUT_TIME := 0;
    signal timer_done   : std_logic := '0';

    -- ===========================================================
    -- Controle de exibição de LEDs
    -- ===========================================================
    signal cur_led      : std_logic_vector(1 downto 0) := "00"; -- LED atual exibido
    signal led_reg      : std_logic_vector(7 downto 0) := (others => '0');
    signal ledr_reg     : std_logic_vector(9 downto 0) := (others => '0');

    -- ===========================================================
    -- Pontuação e flash
    -- ===========================================================
    signal score        : integer range 0 to 99 := 0;
    signal flash_cnt    : integer range 0 to NUM_FLASHES := 0;
    signal flash_state  : std_logic := '0';

    -- Variável auxiliar para ST_CHECK (declarada como sinal)
    signal v_input      : std_logic_vector(1 downto 0) := "00";

    -- ===========================================================
    -- Funções auxiliares - 7 segmentos (ativo baixo)
    -- ===========================================================
    function to_7seg(digit : integer range 0 to 9) return std_logic_vector is
        -- segmentos: gfedcba
        variable seg : std_logic_vector(6 downto 0);
    begin
        case digit is
            when 0 => seg := "1000000";
            when 1 => seg := "1111001";
            when 2 => seg := "0100100";
            when 3 => seg := "0110000";
            when 4 => seg := "0011001";
            when 5 => seg := "0010010";
            when 6 => seg := "0000010";
            when 7 => seg := "1111000";
            when 8 => seg := "0000000";
            when 9 => seg := "0010000";
            when others => seg := "1111111";
        end case;
        return seg;
    end function;

    -- Constante para display apagado
    constant SEG_OFF : std_logic_vector(6 downto 0) := "1111111";
    -- Constante para traço (-) no display
    constant SEG_DASH: std_logic_vector(6 downto 0) := "0111111";

begin

    -- ===========================================================
    -- Debounce para KEY[3:0] (KEY ativos em LOW na DE2-115)
    -- Converte para ativo em HIGH e gera pulso por pressionamento
    -- ===========================================================
    process(CLOCK_50)
        variable key_inv : std_logic_vector(3 downto 0);
    begin
        if rising_edge(CLOCK_50) then
            key_inv := not KEY;  -- inverte para ativo alto

            for i in 0 to 3 loop
                if key_inv(i) = db_stable(i) then
                    db_cnt(i) <= 0;
                else
                    if db_cnt(i) = DEBOUNCE_TIME then
                        db_stable(i) <= key_inv(i);
                        db_cnt(i)    <= 0;
                    else
                        db_cnt(i) <= db_cnt(i) + 1;
                    end if;
                end if;

                -- Pulso de borda de subida após debounce
                key_pressed(i) <= db_stable(i) and not db_prev(i);
                db_prev(i)     <= db_stable(i);
            end loop;
        end if;
    end process;

    -- ===========================================================
    -- LFSR - roda continuamente para gerar aleatoriedade
    -- Polinômio: x^8 + x^6 + x^5 + x^4 + 1
    -- ===========================================================
    lfsr_feedback <= lfsr(7) xor lfsr(5) xor lfsr(4) xor lfsr(3);

    process(CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            lfsr <= lfsr(6 downto 0) & lfsr_feedback;
        end if;
    end process;

    -- ===========================================================
    -- FSM - Processo de transição de estado (síncrono)
    -- ===========================================================
    process(CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            timer_done <= '0';

            case state is

                -- ---------------------------------------------------
                -- ST_IDLE: Aguarda pressionamento do KEY0 para iniciar
                -- ---------------------------------------------------
                when ST_IDLE =>
                    led_reg   <= "00000000";
                    ledr_reg  <= "0000000000";
                    seq_len   <= 0;
                    score     <= 0;
                    flash_cnt <= 0;

                    -- Animação idle: LEDG0 e LEDG6 piscam alternadamente
                    timer <= timer + 1;
                    if timer = CLK_FREQ / 2 then
                        timer    <= 0;
                        led_reg  <= led_reg(6 downto 0) & led_reg(7); -- rotação
                        if led_reg = "00000000" then
                            led_reg <= "10000001"; -- inicializa
                        end if;
                    end if;

                    if key_pressed(0) = '1' then
                        led_reg  <= "00000000";
                        timer    <= 0;
                        state    <= ST_GEN_SEQ;
                    end if;

                -- ---------------------------------------------------
                -- ST_GEN_SEQ: Adiciona um novo elemento à sequência
                -- ---------------------------------------------------
                when ST_GEN_SEQ =>
                    seq_mem(seq_len) <= lfsr(1 downto 0);
                    seq_len          <= seq_len + 1;
                    seq_idx          <= 0;
                    timer            <= 0;
                    state            <= ST_SHOW_LEAD;

                -- ---------------------------------------------------
                -- ST_SHOW_LEAD: Pausa antes de cada LED (200 ms)
                -- ---------------------------------------------------
                when ST_SHOW_LEAD =>
                    led_reg <= "00000000";
                    timer   <= timer + 1;
                    if timer = LED_OFF_TIME then
                        timer    <= 0;
                        cur_led  <= seq_mem(seq_idx);
                        state    <= ST_SHOW_SEQ;
                    end if;

                -- ---------------------------------------------------
                -- ST_SHOW_SEQ: Acende LED por 500 ms
                -- ---------------------------------------------------
                when ST_SHOW_SEQ =>
                    -- Acende o LED correspondente ao elemento atual
                    case cur_led is
                        when "00" => led_reg <= "00000001"; -- LEDG0
                        when "01" => led_reg <= "00000100"; -- LEDG2
                        when "10" => led_reg <= "00010000"; -- LEDG4
                        when "11" => led_reg <= "01000000"; -- LEDG6
                        when others => led_reg <= "00000000";
                    end case;

                    timer <= timer + 1;
                    if timer = LED_ON_TIME then
                        timer   <= 0;
                        led_reg <= "00000000";

                        if seq_idx = seq_len - 1 then
                            -- Fim da exibição, aguarda usuário
                            seq_idx <= 0;
                            timer   <= 0;
                            state   <= ST_WAIT_USER;
                        else
                            seq_idx <= seq_idx + 1;
                            state   <= ST_SHOW_LEAD;
                        end if;
                    end if;

                -- ---------------------------------------------------
                -- ST_WAIT_USER: Aguarda botão (timeout = 5 s)
                -- ---------------------------------------------------
                when ST_WAIT_USER =>
                    led_reg <= "00000000";
                    timer   <= timer + 1;

                    if timer = TIMEOUT_TIME then
                        timer <= 0;
                        state <= ST_LOSE_FLASH;
                    end if;

                    if key_pressed /= "0000" then
                        -- Registra qual botão foi pressionado antes de ir para ST_CHECK
                        if    key_pressed(0) = '1' then v_input <= "00";
                        elsif key_pressed(1) = '1' then v_input <= "01";
                        elsif key_pressed(2) = '1' then v_input <= "10";
                        else                            v_input <= "11";
                        end if;
                        timer <= 0;
                        state <= ST_CHECK;
                    end if;

                -- ---------------------------------------------------
                -- ST_CHECK: Verifica a entrada do usuário
                -- (v_input já foi gravado no ciclo anterior em ST_WAIT_USER)
                -- ---------------------------------------------------
                when ST_CHECK =>
                        -- Acende LED do botão pressionado como feedback
                        case v_input is
                            when "00" => led_reg <= "00000001";
                            when "01" => led_reg <= "00000100";
                            when "10" => led_reg <= "00010000";
                            when others => led_reg <= "01000000";
                        end case;

                        -- Verifica se a entrada bate com a sequência
                        if v_input = seq_mem(seq_idx) then
                            -- Entrada correta
                            if seq_idx = seq_len - 1 then
                                -- Sequência completa: vitória de rodada
                                if score < 99 then
                                    score <= score + 1;
                                end if;
                                timer   <= 0;
                                seq_idx <= 0;
                                state   <= ST_WIN;
                            else
                                -- Continua aguardando próxima entrada
                                seq_idx <= seq_idx + 1;
                                timer   <= 0;
                                state   <= ST_WAIT_USER;
                            end if;
                        else
                            -- Entrada errada
                            timer     <= 0;
                            flash_cnt <= 0;
                            state     <= ST_LOSE_FLASH;
                        end if;

                -- ---------------------------------------------------
                -- ST_WIN: Animação de vitória (todos LEDs piscam 2x)
                -- ---------------------------------------------------
                when ST_WIN =>
                    timer <= timer + 1;
                    if timer < WIN_FLASH_TIME then
                        led_reg <= "01010101"; -- todos acesos
                    elsif timer < WIN_FLASH_TIME * 2 then
                        led_reg <= "00000000";
                    elsif timer < WIN_FLASH_TIME * 3 then
                        led_reg <= "01010101";
                    else
                        led_reg <= "00000000";
                        timer   <= 0;
                        -- Avança para próximo nível se não atingiu limite
                        if seq_len < MAX_SEQ then
                            state <= ST_GEN_SEQ;
                        else
                            -- Venceu o jogo inteiro!
                            state <= ST_LOSE;  -- exibe pontuação máxima
                        end if;
                    end if;

                -- ---------------------------------------------------
                -- ST_LOSE_FLASH: Pisca todos LEDs vermelhos = Game Over
                -- ---------------------------------------------------
                when ST_LOSE_FLASH =>
                    led_reg  <= "00000000";
                    timer    <= timer + 1;

                    if timer < LOSE_FLASH_TIME then
                        ledr_reg <= "1111111111";
                    else
                        ledr_reg <= "0000000000";
                        if timer = LOSE_FLASH_TIME * 2 then
                            timer     <= 0;
                            flash_cnt <= flash_cnt + 1;
                        end if;
                    end if;

                    if flash_cnt = NUM_FLASHES then
                        ledr_reg  <= "0000000000";
                        timer     <= 0;
                        state     <= ST_LOSE;
                    end if;

                -- ---------------------------------------------------
                -- ST_LOSE: Exibe score final, aguarda KEY0 para reset
                -- ---------------------------------------------------
                when ST_LOSE =>
                    led_reg  <= "00000000";
                    ledr_reg <= "0000000000";

                    if key_pressed(0) = '1' then
                        timer <= 0;
                        state <= ST_IDLE;
                    end if;

                when others =>
                    state <= ST_IDLE;

            end case;
        end if;
    end process;

    -- ===========================================================
    -- Saídas para LEDs
    -- ===========================================================
    LEDG <= led_reg;
    LEDR <= ledr_reg;

    -- ===========================================================
    -- Display de 7 segmentos - Pontuação (dezenas / unidades)
    -- ===========================================================
    process(score, state, seq_len)
    begin
        HEX0 <= to_7seg(score mod 10);
        HEX1 <= to_7seg(score / 10);

        -- HEX2 mostra nível atual, HEX3 fica apagado
        if seq_len > 0 then
            HEX2 <= to_7seg(seq_len mod 10);
        else
            HEX2 <= SEG_OFF;
        end if;

        HEX3 <= SEG_OFF;

        -- No estado IDLE mostra traços para indicar pronto
        if state = ST_IDLE then
            HEX0 <= SEG_DASH;
            HEX1 <= SEG_DASH;
            HEX2 <= SEG_DASH;
            HEX3 <= SEG_DASH;
        end if;
    end process;

end architecture rtl;
