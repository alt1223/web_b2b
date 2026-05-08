'use client'
import { useState, useEffect, useRef } from "react";

const LANGUAGES = [
    { code: 'en', name: 'English' },
    { code: 'zh', name: '中文' },
];

function getCookie(name) {
    if (typeof document === 'undefined') return '';
    const m = document.cookie.match(new RegExp('(?:^|;\\s*)' + name + '=([^;]+)'));
    return m ? decodeURIComponent(m[1]) : '';
}

function setLangCookie(code) {
    const expires = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toUTCString();
    document.cookie = `lang=${encodeURIComponent(code)}; expires=${expires}; path=/`;
}

export default function SwitchLangB({colorClass="bg-white text-gray-500 px-4 py-2 border-[1px] border-gray-300 rounded-full shadow-sm"}) {
    const [showLanguageMenu, setShowLanguageMenu] = useState(false);
    const [currentLanguage, setCurrentLanguage] = useState('en');
    const [mounted, setMounted] = useState(false);
    const [showButton, setShowButton] = useState(true);
    const menuRef = useRef(null);
    const buttonRef = useRef(null);
    const lastScrollY = useRef(0);

    useEffect(() => {
        const c = getCookie('lang');
        if (c && LANGUAGES.some(l => l.code === c)) setCurrentLanguage(c);
        setMounted(true);
    }, []);

    useEffect(() => {
        const handleClickOutside = (event) => {
            if (menuRef.current && !menuRef.current.contains(event.target) &&
                buttonRef.current && !buttonRef.current.contains(event.target)) {
                setShowLanguageMenu(false);
            }
        };
        document.addEventListener('click', handleClickOutside);
        return () => document.removeEventListener('click', handleClickOutside);
    }, []);

    useEffect(() => {
        const handleScroll = () => {
            const currentScrollY = window.scrollY;
            if (currentScrollY > 100) {
                setShowButton(currentScrollY <= lastScrollY.current);
            } else {
                setShowButton(true);
            }
            lastScrollY.current = currentScrollY;
        };
        window.addEventListener('scroll', handleScroll, { passive: true });
        return () => window.removeEventListener('scroll', handleScroll);
    }, []);

    const handleSelect = (code) => {
        if (code === currentLanguage) { setShowLanguageMenu(false); return; }
        setLangCookie(code);
        window.location.reload();
    };

    const buttonPosition = "left-2 bottom-2 lg:left-auto lg:bottom-auto lg:top-5 lg:right-4";
    const menuPosition = "left-2 bottom-[40px] lg:left-auto lg:bottom-auto lg:top-[52px] lg:right-4";
    const transitionStyle = "transition-all duration-300 ease-in-out";
    const buttonVisibilityClass = showButton ? "opacity-100 pointer-events-auto" : "opacity-0 pointer-events-none";

    return (
        <>
            <div
                className={`language-selector fixed ${buttonPosition} z-[60] ${transitionStyle} ${buttonVisibilityClass}`}
                ref={buttonRef}
                onMouseEnter={() => setShowLanguageMenu(true)}
                onMouseLeave={() => setShowLanguageMenu(false)}
            >
                <button
                    className={`flex items-center ${colorClass} focus:outline-none`}
                    onClick={() => setShowLanguageMenu(!showLanguageMenu)}
                >
                    <svg xmlns="http://www.w3.org/2000/svg" className="w-3.5 h-3.5" viewBox="0 0 16 16">
                        <path fill="currentColor" fillRule="evenodd"
                              d="M8 14.5c.23 0 .843-.226 1.487-1.514c.306-.612.563-1.37.742-2.236H5.771c.179.866.436 1.624.742 2.236C7.157 14.274 7.77 14.5 8 14.5M5.554 9.25a14.4 14.4 0 0 1 0-2.5h4.892a14.5 14.5 0 0 1 0 2.5zm6.203 1.5c-.224 1.224-.593 2.308-1.066 3.168a6.53 6.53 0 0 0 3.2-3.168zm2.623-1.5h-2.43a16 16 0 0 0 0-2.5h2.429a6.5 6.5 0 0 1 0 2.5Zm-10.331 0H1.62a6.5 6.5 0 0 1 0-2.5h2.43a16 16 0 0 0 0 2.5Zm-1.94 1.5h2.134c.224 1.224.593 2.308 1.066 3.168a6.53 6.53 0 0 1-3.2-3.168m3.662-5.5h4.458c-.179-.866-.436-1.624-.742-2.236C8.843 1.726 8.23 1.5 8 1.5s-.843.226-1.487 1.514c-.306.612-.563 1.37-.742 2.236m5.986 0h2.134a6.53 6.53 0 0 0-3.2-3.168c.473.86.842 1.944 1.066 3.168M5.31 2.082c-.473.86-.842 1.944-1.066 3.168H2.109a6.53 6.53 0 0 1 3.2-3.168ZM8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0"
                              clipRule="evenodd"/>
                    </svg>
                    <span className="ml-1 text-xs">{LANGUAGES.find(l => l.code === currentLanguage)?.name || 'English'}</span>
                    <svg className="h-3.5 w-3.5 ml-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                    </svg>
                </button>
            </div>

            {mounted && (
                <div
                    ref={menuRef}
                    className={`fixed ${menuPosition} bg-white border-[1px] border-gray-300 rounded-md shadow-lg w-28 z-[65] transition-all duration-200 ease-in-out transform origin-top-right ${
                        showLanguageMenu && showButton
                            ? 'opacity-100 scale-100'
                            : 'opacity-0 scale-95 pointer-events-none'
                    }`}
                    onMouseEnter={() => setShowLanguageMenu(true)}
                    onMouseLeave={() => setShowLanguageMenu(false)}
                >
                    <div className="py-1">
                        {LANGUAGES.map((l) => (
                            <button
                                key={l.code}
                                onClick={() => handleSelect(l.code)}
                                className={`block w-full text-left px-4 py-2 text-sm hover:bg-gray-100 ${l.code === currentLanguage ? 'text-blue-600 font-medium' : 'text-gray-700'}`}
                            >
                                {l.name}
                            </button>
                        ))}
                    </div>
                </div>
            )}
        </>
    );
}
